import fs from 'node:fs';

const INTERMEDIATE_VIEWPORTS = [
  { name: 'android-compact', width: 360, height: 740 },
  { name: 'iphone-plus', width: 414, height: 896 },
  { name: 'surface-fold', width: 540, height: 720 },
  { name: 'intermediate-tab', width: 720, height: 960 },
  { name: 'ipad-air-port', width: 820, height: 1180 },
  { name: 'surface-pro-port', width: 912, height: 1368 },
  { name: 'ipad-air-land', width: 1180, height: 820 },
  { name: 'common-laptop', width: 1366, height: 768 },
  { name: 'iphone-landscape', width: 667, height: 375 },
  { name: 'iphone-pro-land', width: 844, height: 390 }
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

async function run() {
  console.log("==================================================");
  console.log("Testing Intermediate Widths, Landscapes & Zoom");
  console.log("==================================================");

  let totalTests = 0;
  let passedTests = 0;
  let failedTests = 0;

  for (const p of PAGES) {
    const pageUrl = `http://127.0.0.1:8080${p}`;
    const newTabRes = await fetch(`http://127.0.0.1:9222/json/new?${encodeURIComponent(pageUrl)}`, { method: 'PUT' });
    const tab = await newTabRes.json();
    const cdp = new CDPClient(tab.webSocketDebuggerUrl);
    await cdp.connect();

    await cdp.send('Page.enable');
    await cdp.send('DOM.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Network.enable');
    await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
    await cdp.send('Page.reload', { ignoreCache: true });
    await new Promise(r => setTimeout(r, 400));

    // Test intermediate viewports
    for (const vp of INTERMEDIATE_VIEWPORTS) {
      totalTests++;
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: vp.width,
        height: vp.height,
        deviceScaleFactor: 2,
        mobile: vp.width < 800
      });
      await new Promise(r => setTimeout(r, 150));

      const evalRes = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const doc = document.documentElement;
          const body = document.body;
          const clientWidth = doc.clientWidth;
          const scrollWidth = Math.max(doc.scrollWidth, body.scrollWidth);
          return { clientWidth, scrollWidth, diff: scrollWidth - clientWidth, hasOverflow: scrollWidth > clientWidth };
        })()`,
        returnByValue: true
      });

      const res = evalRes.result.value;
      if (!res.hasOverflow) {
        passedTests++;
      } else {
        failedTests++;
        console.error(`❌ Overflow on ${p} at ${vp.width}x${vp.height} (${vp.name}): +${res.diff}px`);
      }
    }

    // Test Zoom / text scaling at 125% and 150%
    for (const zoom of [1.25, 1.5]) {
      totalTests++;
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: 375,
        height: 667,
        deviceScaleFactor: 2,
        mobile: true
      });
      await cdp.send('Emulation.setPageScaleFactor', { pageScaleFactor: zoom });
      await new Promise(r => setTimeout(r, 150));

      const zoomEval = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const doc = document.documentElement;
          const body = document.body;
          const clientWidth = doc.clientWidth;
          const scrollWidth = Math.max(doc.scrollWidth, body.scrollWidth);
          return { clientWidth, scrollWidth, diff: scrollWidth - clientWidth, hasOverflow: scrollWidth > clientWidth };
        })()`,
        returnByValue: true
      });

      const zRes = zoomEval.result.value;
      if (!zRes.hasOverflow) {
        passedTests++;
      } else {
        failedTests++;
        console.error(`❌ Overflow under ${zoom * 100}% zoom on ${p}: +${zRes.diff}px`);
      }
      // Reset scale
      await cdp.send('Emulation.setPageScaleFactor', { pageScaleFactor: 1 });
    }

    await cdp.close();
    await fetch(`http://127.0.0.1:9222/json/close/${tab.id}`);
  }

  console.log("\n==================================================");
  console.log(`Intermediate & Zoom Verification Complete!`);
  console.log(`Total Scenarios: ${totalTests} | Passed: ${passedTests} | Failed: ${failedTests}`);
  console.log("==================================================");

  if (failedTests > 0) process.exit(1);
}

run().catch(err => {
  console.error("Error during intermediate verification:", err);
  process.exit(1);
});
