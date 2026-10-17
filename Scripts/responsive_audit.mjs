import fs from 'node:fs';
import path from 'node:path';

const ARTIFACTS_DIR = process.env.ARTIFACTS_DIR || path.resolve(import.meta.dirname, '../dist/screenshots');
const MODE = process.argv[2] || 'audit';
const OUTPUT_DIR = path.join(ARTIFACTS_DIR, `screenshots_${MODE}`);

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

const VIEWPORTS = [
  { name: 'narrow-mobile', width: 320, height: 640 },
  { name: 'std-mobile', width: 375, height: 667 },
  { name: 'large-mobile', width: 430, height: 932 },
  { name: 'small-tablet', width: 600, height: 800 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'large-tablet', width: 1024, height: 768 },
  { name: 'laptop', width: 1280, height: 800 },
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'large-desktop', width: 1920, height: 1080 }
];

const PAGES = [
  { name: 'home', path: '/' },
  { name: 'features', path: '/features/' },
  { name: 'download', path: '/download/' },
  { name: 'docs', path: '/docs/' },
  { name: 'changelog', path: '/changelog/' },
  { name: 'contributing', path: '/contributing/' },
  { name: 'privacy', path: '/privacy/' },
  { name: 'support', path: '/support/' },
  { name: '404', path: '/404.html' }
];

class CDPClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.id = 1;
    this.callbacks = new Map();
    this.events = [];
  }

  async connect() {
    this.ws = new WebSocket(this.wsUrl);
    await new Promise((resolve, reject) => {
      this.ws.onopen = resolve;
      this.ws.onerror = reject;
    });

    this.ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id && this.callbacks.has(msg.id)) {
        const { resolve, reject } = this.callbacks.get(msg.id);
        this.callbacks.delete(msg.id);
        if (msg.error) {
          reject(new Error(msg.error.message));
        } else {
          resolve(msg.result);
        }
      } else if (msg.method) {
        this.events.push(msg);
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

async function runAudit() {
  console.log(`Starting responsive audit in mode: ${MODE}`);
  console.log(`Screenshots will be saved to: ${OUTPUT_DIR}`);

  const results = [];

  for (const page of PAGES) {
    const pageUrl = `http://127.0.0.1:8080${page.path}`;
    console.log(`\n========================================`);
    console.log(`Auditing Page: ${page.name} (${page.path})`);
    console.log(`========================================`);

    // Create a new tab
    const newTabRes = await fetch(`http://127.0.0.1:9222/json/new?${encodeURIComponent(pageUrl)}`, { method: 'PUT' });
    const tab = await newTabRes.json();
    const cdp = new CDPClient(tab.webSocketDebuggerUrl);
    await cdp.connect();

    await cdp.send('Page.enable');
    await cdp.send('DOM.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    await cdp.send('Network.enable');
    await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
    await cdp.send('Page.reload', { ignoreCache: true });

    // Wait for page to finish loading after cache-disabled reload
    await new Promise(r => setTimeout(r, 600));

    for (const vp of VIEWPORTS) {
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: vp.width,
        height: vp.height,
        deviceScaleFactor: 2,
        mobile: vp.width < 768,
        fitWindow: false
      });

      // Small pause for layout reflow
      await new Promise(r => setTimeout(r, 200));

      // 1. Check Document-level Horizontal Overflow
      const overflowEval = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const docEl = document.documentElement;
          const body = document.body;
          const clientWidth = docEl.clientWidth;
          const scrollWidth = Math.max(docEl.scrollWidth, body.scrollWidth);
          const hasOverflow = scrollWidth > clientWidth;
          
          let offendingElements = [];
          if (hasOverflow) {
            const all = document.querySelectorAll('*');
            for (const el of all) {
              // Ignore elements inside intentional contained horizontal scrollers (e.g. table-container, pre)
              let parent = el.parentElement;
              let inScrollContainer = false;
              while (parent && parent !== document.body && parent !== document.documentElement) {
                const overflowX = window.getComputedStyle(parent).overflowX;
                if (overflowX === 'auto' || overflowX === 'scroll') {
                  inScrollContainer = true;
                  break;
                }
                parent = parent.parentElement;
              }
              if (inScrollContainer) continue;

              const rect = el.getBoundingClientRect();
              if (rect.right > clientWidth + 1 || rect.left < -1) {
                offendingElements.push({
                  tag: el.tagName.toLowerCase(),
                  id: el.id,
                  className: el.className ? String(el.className) : '',
                  rect: { left: Math.round(rect.left), right: Math.round(rect.right), width: Math.round(rect.width) },
                  snippet: (el.innerText || el.textContent || '').trim().slice(0, 60)
                });
              }
            }
          }
          return {
            clientWidth,
            scrollWidth,
            hasOverflow,
            diff: scrollWidth - clientWidth,
            offendingCount: offendingElements.length,
            offendingElements: offendingElements.slice(0, 10)
          };
        })()`,
        returnByValue: true
      });

      const overflow = overflowEval.result.value;

      // 2. Navigation bar & Header checks
      const headerEval = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const header = document.querySelector('.site-header');
          const headerContainer = document.querySelector('.header-container');
          const brand = document.querySelector('.brand');
          const navLinks = document.querySelector('.nav-links');
          const mobileBtn = document.querySelector('.mobile-menu-btn');
          const navActions = document.querySelector('.nav-actions');

          const headerRect = header ? header.getBoundingClientRect() : null;
          const brandRect = brand ? brand.getBoundingClientRect() : null;
          const navRect = navLinks ? navLinks.getBoundingClientRect() : null;
          const mobileBtnRect = mobileBtn ? mobileBtn.getBoundingClientRect() : null;

          const isMobileBtnVisible = mobileBtn ? window.getComputedStyle(mobileBtn).display !== 'none' : false;
          const isNavLinksVisible = navLinks ? window.getComputedStyle(navLinks).display !== 'none' : false;

          return {
            hasHeader: !!header,
            headerHeight: headerRect ? Math.round(headerRect.height) : 0,
            isMobileBtnVisible,
            isNavLinksVisible,
            navLinksClass: navLinks ? navLinks.className : '',
            brandWidth: brandRect ? Math.round(brandRect.width) : 0
          };
        })()`,
        returnByValue: true
      });

      const headerState = headerEval.result.value;

      // 3. Touch targets check (for interactive elements)
      const touchEval = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const interactive = Array.from(document.querySelectorAll('a, button, input, select, textarea'));
          const smallTargets = [];
          for (const el of interactive) {
            const rect = el.getBoundingClientRect();
            // Only visible elements
            if (rect.width > 0 && rect.height > 0 && window.getComputedStyle(el).visibility !== 'hidden' && window.getComputedStyle(el).display !== 'none') {
              const isInlineLink = el.tagName === 'A' && el.closest('p, li, td') && window.getComputedStyle(el).display === 'inline';
              if (!isInlineLink && (rect.width < 40 || rect.height < 40)) {
                smallTargets.push({
                  tag: el.tagName.toLowerCase(),
                  id: el.id,
                  className: el.className ? String(el.className).slice(0, 40) : '',
                  size: Math.round(rect.width) + 'x' + Math.round(rect.height),
                  text: (el.innerText || el.getAttribute('aria-label') || '').trim().slice(0, 30)
                });
              }
            }
          }
          return {
            totalInteractive: interactive.length,
            smallCount: smallTargets.length,
            smallTargets: smallTargets.slice(0, 8)
          };
        })()`,
        returnByValue: true
      });

      const touchState = touchEval.result.value;

      // 4. Capture screenshot
      const screenshotRes = await cdp.send('Page.captureScreenshot', {
        format: 'png',
        captureBeyondViewport: false
      });

      const screenshotFilename = `${page.name}_${vp.width}px.png`;
      const screenshotPath = path.join(OUTPUT_DIR, screenshotFilename);
      fs.writeFileSync(screenshotPath, Buffer.from(screenshotRes.data, 'base64'));

      const vpResult = {
        page: page.name,
        path: page.path,
        viewport: vp.name,
        width: vp.width,
        height: vp.height,
        hasOverflow: overflow.hasOverflow,
        scrollWidth: overflow.scrollWidth,
        clientWidth: overflow.clientWidth,
        diff: overflow.diff,
        offendingCount: overflow.offendingCount,
        offendingElements: overflow.offendingElements,
        header: headerState,
        smallTargetsCount: touchState.smallCount,
        smallTargets: touchState.smallTargets,
        screenshot: screenshotFilename
      };

      results.push(vpResult);

      const status = overflow.hasOverflow ? `❌ OVERFLOW (+${overflow.diff}px)` : `✓ PASS`;
      console.log(`  [${vp.width}px - ${vp.name.padEnd(14)}] ${status} | Header: navLinks=${headerState.isNavLinksVisible ? 'shown' : 'hidden'}, menuBtn=${headerState.isMobileBtnVisible ? 'visible' : 'hidden'} | Small touch targets: ${touchState.smallCount}`);
      if (overflow.hasOverflow) {
        console.log(`     Offending:`, overflow.offendingElements.map(e => `${e.tag}.${e.className} (w:${e.rect.width}, r:${e.rect.right})`).join(', '));
      }
    }

    // Test mobile menu interactivity specifically at 375px
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 375,
      height: 667,
      deviceScaleFactor: 2,
      mobile: true,
      fitWindow: false
    });
    await new Promise(r => setTimeout(r, 200));

    const menuInteraction = await cdp.send('Runtime.evaluate', {
      expression: `(async () => {
        const btn = document.querySelector('.mobile-menu-btn');
        const nav = document.querySelector('.nav-links');
        if (!btn || !nav) return { error: 'Button or nav missing' };

        const initialOpen = nav.classList.contains('open');
        const initialAria = btn.getAttribute('aria-expanded');

        // Click to open
        btn.click();
        const afterClickOpen = nav.classList.contains('open');
        const afterClickAria = btn.getAttribute('aria-expanded');
        const navRect = nav.getBoundingClientRect();

        // Check if menu is accessible or overflowing
        const menuFits = navRect.left >= 0 && navRect.right <= window.innerWidth + 1;

        // Click to close
        btn.click();
        const afterSecondClickOpen = nav.classList.contains('open');

        return {
          hasBtn: true,
          initialOpen,
          afterClickOpen,
          afterClickAria,
          afterSecondClickOpen,
          menuFits,
          menuWidth: Math.round(navRect.width)
        };
      })()`,
      awaitPromise: true,
      returnByValue: true
    });

    console.log(`  Mobile Menu Interaction Test (375px):`, menuInteraction.result.value);

    await cdp.close();
    await fetch(`http://127.0.0.1:9222/json/close/${tab.id}`);
  }

  const reportPath = path.join(ARTIFACTS_DIR, `audit_report_${MODE}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
  console.log(`\nAudit complete! Full JSON report written to: ${reportPath}`);
}

runAudit().catch(err => {
  console.error("Audit failed:", err);
  process.exit(1);
});
