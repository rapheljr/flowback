import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const CDP_PORT = 9224;
const HTTP_PORT = 8085;
const CHROME_PATH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const WEBSITE_DIR = path.resolve(import.meta.dirname, '../Website');

const TEST_VIEWPORTS = [
  { name: 'narrow-mobile', width: 320, height: 640 },
  { name: 'mobile', width: 375, height: 667 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'large-tablet', width: 1024, height: 768 },
  { name: 'desktop', width: 1440, height: 900 }
];

const PAGES = [
  '/',
  '/features/',
  '/download/',
  '/docs/',
  '/changelog/',
  '/contributing/',
  '/privacy/',
  '/404.html'
];

class CDPClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.id = 1;
    this.callbacks = new Map();
    this.consoleErrors = [];
  }

  async connect() {
    this.ws = new WebSocket(this.wsUrl);
    await new Promise((res, rej) => {
      this.ws.onopen = res;
      this.ws.onerror = rej;
    });
    this.ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id && this.callbacks.has(msg.id)) {
        const { resolve, reject } = this.callbacks.get(msg.id);
        this.callbacks.delete(msg.id);
        if (msg.error) reject(new Error(msg.error.message));
        else resolve(msg.result);
      } else if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') {
        this.consoleErrors.push(msg.params.args.map(a => a.value || a.description).join(' '));
      }
    };
  }

  send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const msgId = this.id++;
      this.callbacks.set(msgId, { resolve, reject });
      this.ws.send(JSON.stringify({ id: msgId, method, params }));
    });
  }

  async close() {
    this.ws.close();
  }
}

// Simple Static HTTP Server for Testing
function startHttpServer() {
  const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.svg': 'image/svg+xml',
    '.json': 'application/json',
    '.xml': 'application/xml',
    '.txt': 'text/plain'
  };

  const server = http.createServer((req, res) => {
    let reqPath = req.url.split('?')[0];
    if (reqPath.endsWith('/')) reqPath += 'index.html';
    const filePath = path.join(WEBSITE_DIR, reqPath);

    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.writeHead(404);
        res.end('Not Found');
        return;
      }
      const ext = path.extname(filePath);
      res.writeHead(200, {
        'Content-Type': mimeTypes[ext] || 'application/octet-stream',
        'Cache-Control': 'no-store'
      });
      res.end(data);
    });
  });

  return new Promise(resolve => {
    server.listen(HTTP_PORT, '127.0.0.1', () => {
      resolve(server);
    });
  });
}

async function startChrome() {
  if (!fs.existsSync(CHROME_PATH)) {
    console.warn(`[WARN] Google Chrome not found at ${CHROME_PATH}. Skipping browser responsive suite.`);
    return null;
  }

  const chromeProc = spawn(CHROME_PATH, [
    '--headless=new',
    `--remote-debugging-port=${CDP_PORT}`,
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    'about:blank'
  ], { stdio: 'ignore' });

  // Wait for CDP port to open
  for (let i = 0; i < 30; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`);
      if (res.ok) return chromeProc;
    } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('Chrome failed to start CDP listener in time');
}

async function run() {
  console.log("==========================================");
  console.log("Running Automated Responsive Suite");
  console.log("==========================================");

  const server = await startHttpServer();
  const chromeProc = await startChrome();
  if (!chromeProc) {
    server.close();
    process.exit(0);
  }

  let assertions = 0;
  let failures = 0;

  try {
    for (const pagePath of PAGES) {
      const pageUrl = `http://127.0.0.1:${HTTP_PORT}${pagePath}`;
      const newTabRes = await fetch(`http://127.0.0.1:${CDP_PORT}/json/new?${encodeURIComponent(pageUrl)}`, { method: 'PUT' });
      const tab = await newTabRes.json();
      const cdp = new CDPClient(tab.webSocketDebuggerUrl);
      await cdp.connect();

      await cdp.send('Page.enable');
      await cdp.send('DOM.enable');
      await cdp.send('Runtime.enable');
      await cdp.send('Network.enable');
      await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
      await cdp.send('Page.reload', { ignoreCache: true });
      await new Promise(r => setTimeout(r, 300));

      console.log(`Checking ${pagePath}...`);

      for (const vp of TEST_VIEWPORTS) {
        await cdp.send('Emulation.setDeviceMetricsOverride', {
          width: vp.width,
          height: vp.height,
          deviceScaleFactor: 2,
          mobile: vp.width < 768
        });
        await new Promise(r => setTimeout(r, 100));

        // 1. Assert No Horizontal Document Overflow
        assertions++;
        const overflowRes = await cdp.send('Runtime.evaluate', {
          expression: `(() => {
            const doc = document.documentElement;
            const body = document.body;
            const clientWidth = doc.clientWidth;
            const scrollWidth = Math.max(doc.scrollWidth, body.scrollWidth);
            return { clientWidth, scrollWidth, hasOverflow: scrollWidth > clientWidth, diff: scrollWidth - clientWidth };
          })()`,
          returnByValue: true
        });

        const ofData = overflowRes.result.value;
        if (ofData.hasOverflow) {
          console.error(`  ❌ [${vp.width}px] Horizontal overflow on ${pagePath}: +${ofData.diff}px`);
          failures++;
        } else {
          console.log(`  ✓ [${vp.width}px] Layout fits clientWidth (${ofData.clientWidth}px)`);
        }

        // 2. Assert Images stay within containers
        assertions++;
        const imageRes = await cdp.send('Runtime.evaluate', {
          expression: `(() => {
            const imgs = Array.from(document.querySelectorAll('img, svg'));
            const clientWidth = document.documentElement.clientWidth;
            const overflowing = [];
            for (const img of imgs) {
              const r = img.getBoundingClientRect();
              if (r.width > clientWidth + 1) {
                overflowing.push({ tag: img.tagName, src: img.src || img.getAttribute('src'), width: r.width });
              }
            }
            return { total: imgs.length, overflowingCount: overflowing.length };
          })()`,
          returnByValue: true
        });
        const imgData = imageRes.result.value;
        if (imgData.overflowingCount > 0) {
          console.error(`  ❌ [${vp.width}px] ${imgData.overflowingCount} image(s) exceed clientWidth`);
          failures++;
        }
      }

      // 3. Test Mobile Navigation Usability at 375px
      assertions++;
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: 375,
        height: 667,
        deviceScaleFactor: 2,
        mobile: true
      });
      await new Promise(r => setTimeout(r, 100));

      const menuTest = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const btn = document.querySelector('.mobile-menu-btn');
          const nav = document.querySelector('.nav-links');
          if (!btn || !nav) return { pass: false, reason: 'missing button or nav' };

          // Open
          btn.click();
          const openState = nav.classList.contains('open') && btn.getAttribute('aria-expanded') === 'true';

          // Close
          btn.click();
          const closeState = !nav.classList.contains('open') && btn.getAttribute('aria-expanded') === 'false';

          return { pass: openState && closeState, openState, closeState };
        })()`,
        returnByValue: true
      });

      if (!menuTest.result.value.pass) {
        console.error(`  ❌ Mobile navigation toggle failed on ${pagePath}:`, menuTest.result.value);
        failures++;
      } else {
        console.log(`  ✓ Mobile menu button opens and closes accessible navigation`);
      }

      // 4. Assert no critical JS errors
      assertions++;
      if (cdp.consoleErrors.length > 0) {
        console.error(`  ❌ Console errors detected on ${pagePath}:`, cdp.consoleErrors);
        failures++;
      } else {
        console.log(`  ✓ Console clean (0 uncaught errors)`);
      }

      await cdp.close();
      await fetch(`http://127.0.0.1:${CDP_PORT}/json/close/${tab.id}`);
    }
  } finally {
    server.close();
    chromeProc.kill();
  }

  console.log("==========================================");
  console.log(`Responsive Suite Summary: ${assertions} assertions, ${failures} failures`);
  console.log("==========================================");

  if (failures > 0) process.exit(1);
}

run().catch(err => {
  console.error("Test suite runtime error:", err);
  process.exit(1);
});
