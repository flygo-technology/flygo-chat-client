// WebKit check of the Ký số page scripts in iframes, with the native side of iOS / macOS emulated: every
// reply of the MagicSignNative web message listener lands in the main frame (flutter_inappwebview evaluates
// it there), whichever frame sent the request.
//
//   node tool/kyso_frames_probe/run.mjs   (PW=playwright-core module, PW_WEBKIT=WebKit pw_run.sh if not the bundled one)
//
// The page (main origin) has a same-origin iframe and a cross-origin iframe. Each opens
// ws://localhost:11984/plugin like MISA meInvoice and sends GetRawVersion; the fake engine echoes it.
// Expected: main and same-origin iframe get the echo; the cross-origin iframe gets nothing.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const assets = path.resolve(here, '../../assets/magicsign');
const pw = await import(process.env.PW || 'playwright-core');
const webkit = pw[process.env.PW_ENGINE || 'webkit'];

const pageBridge = fs.readFileSync(path.join(assets, 'app/page-bridge.js'), 'utf8');
const inject = fs.readFileSync(path.join(assets, 'ext/inject.js'), 'utf8');

const probe = (name) => `<!doctype html><meta charset="utf-8"><body><script>
  setTimeout(() => {
    const ws = new WebSocket("ws://localhost:11984/plugin");
    ws.onopen = () => ws.send(JSON.stringify({ action: "GetRawVersion", from: ${JSON.stringify(name)} }));
    ws.onmessage = (e) => { window.__result = "msg " + e.data; };
    ws.onerror = () => { window.__result = window.__result || "error"; };
  }, 300);
</script>`;

const server = http.createServer((req, res) => {
  const host = req.headers.host;
  res.setHeader('content-type', 'text/html; charset=utf-8');
  if (req.url === '/main') {
    const port = host.split(':')[1];
    res.end(probe('main') + `<iframe src="/child"></iframe><iframe src="http://localhost:${port}/child"></iframe>`);
  } else if (req.url === '/child') {
    res.end(probe(host.startsWith('localhost') ? 'cross' : 'same'));
  } else {
    res.statusCode = 404;
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;

const browser = await webkit.launch(process.env.PW_WEBKIT ? { executablePath: process.env.PW_WEBKIT } : {});
const page = await browser.newPage();
const sockets = new Map();

// Native side: requests from any frame, replies only to the main frame.
await page.exposeBinding('__nativePost', async ({ frame }, data) => {
  const message = JSON.parse(data);
  const reply = (body) =>
    page.mainFrame().evaluate((text) => window.__nativeIn && window.__nativeIn(text), JSON.stringify({ fid: message.fid, ...body }));
  if (message.k === 'hello') return reply({ k: 'config', config: { enabled: true, ports: [11984], debug: null }, changed: false });
  if (message.k !== 'port') return;
  const inner = message.message;
  if (inner.t === 'ws_open') {
    sockets.set(`${message.fid}:${inner.id}`, frame.url());
    return reply({ k: 'port', message: { t: 'ws_opened', id: inner.id, protocol: '' } });
  }
  if (inner.t === 'ws_send') return reply({ k: 'port', message: { t: 'ws_msg', id: inner.id, text: `echo:${inner.text}` } });
});

const fakeNative = `(() => {
  const listeners = new Set();
  if (window.top === window) window.__nativeIn = (data) => listeners.forEach((fn) => fn({ data }));
  window.MagicSignNative = {
    postMessage: (data) => window.__nativePost(data),
    addEventListener: (type, fn) => { if (type === 'message') listeners.add(fn); },
  };
})();`;
// Same order as the app: listener object, page-bridge.js, inject.js, in every frame.
await page.addInitScript({ content: `${fakeNative}\n${pageBridge}\n${inject}` });

await page.goto(`http://127.0.0.1:${port}/main`);
await page.waitForTimeout(3000);
const results = {};
for (const frame of page.frames()) {
  const name = frame === page.mainFrame() ? 'main' : frame.url().includes('localhost') ? 'cross' : 'same';
  results[name] = await frame.evaluate(() => window.__result || null);
}
await browser.close();
server.close();

console.log(JSON.stringify(results, null, 2));
const ok = /echo:.*"main"/.test(results.main || '') && /echo:.*"same"/.test(results.same || '') && !/echo/.test(results.cross || '');
console.log(ok ? 'PASS' : 'FAIL');
process.exit(ok ? 0 : 1);
