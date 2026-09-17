import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, readFile, writeFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, extname } from 'node:path';
import assert from 'node:assert/strict';

const site = resolve(process.argv[2] ?? 'dist');
const output = await mkdtemp(join(tmpdir(), 'sidey-web-browser-'));
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (!pathname.startsWith('/SIDEY/')) { res.writeHead(404).end(); return; }
    let file = resolve(site, '.' + pathname.slice('/SIDEY'.length));
    if (!file.startsWith(site + '/')) throw new Error('path');
    if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
    const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml' }[extname(file)] ?? 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime }).end(await readFile(file));
  } catch { res.writeHead(404).end(); }
});
await new Promise(done => server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = spawn(process.env.CHROME_BIN ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--no-first-run', '--no-default-browser-check',
  `--user-data-dir=${output}/profile`, '--remote-debugging-port=0', 'about:blank',
], { stdio: 'ignore' });
const pause = ms => new Promise(done => setTimeout(done, ms));
let socket;
try {
  let port;
  for (let i = 0; i < 100; i++) {
    try { port = (await readFile(`${output}/profile/DevToolsActivePort`, 'utf8')).split('\n')[0]; break; }
    catch { await pause(100); }
  }
  assert.ok(port, 'Chrome debugging endpoint');
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((done, reject) => { socket.onopen = done; socket.onerror = reject; });
  const pending = new Map(); let sequence = 0;
  const token = 'A'.repeat(43);
  let requests = 0;
  let unavailable = false;
  const cdp = (method, params = {}) => new Promise((done, reject) => {
    const id = ++sequence;
    pending.set(id, { done, reject }); socket.send(JSON.stringify({ id, method, params }));
  });
  socket.onmessage = async event => {
    const value = JSON.parse(event.data);
    if (value.id) {
      const task = pending.get(value.id); pending.delete(value.id);
      value.error ? task?.reject(new Error(JSON.stringify(value.error))) : task?.done(value.result);
    } else if (value.method === 'Fetch.requestPaused') {
      const { requestId, request } = value.params;
      let body;
      if (request.url.includes('api.sidey.app/api/commerce/')) {
        if (request.method === 'OPTIONS') {
          await cdp('Fetch.fulfillRequest', { requestId, responseCode: 204,
            responseHeaders: [{ name: 'Access-Control-Allow-Origin', value: origin },
              { name: 'Access-Control-Allow-Methods', value: 'POST' }, { name: 'Access-Control-Allow-Headers', value: 'content-type' }] });
          return;
        }
        requests++;
        const input = JSON.parse(request.postData);
        if (unavailable) {
          await cdp('Fetch.fulfillRequest', { requestId, responseCode: 503,
            responseHeaders: [{ name: 'Content-Type', value: 'application/json' }, { name: 'Access-Control-Allow-Origin', value: origin }],
            body: Buffer.from(JSON.stringify({code:'commerce_not_configured'})).toString('base64') });
          return;
        }
        assert.equal(input.token, token);
        body = request.url.endsWith('/complete') ? { completed: true, status: 'approved' } : {
          orderId: '11111111-1111-4111-8111-111111111111', productId: 'character_tree',
          orderName: 'SIDEY 트리 캐릭터', amount: 7900, currency: 'KRW', policyVersion: 'fixture-v1',
          policyNotice: '구매 조건과 환불 안내를 확인했습니다.', requiresConsent: input.action === 'prepare',
          ...(input.action === 'authorize' ? { storeId: 'fixture', channelKey: 'fixture',
            paymentId: 'sidey-fixture-payment', payMethod: 'EASY_PAY', portoneCurrency: 'CURRENCY_KRW',
            redirectUrl: `${origin}/SIDEY/checkout-result/#token=${token}` } : {}),
        };
        await cdp('Fetch.fulfillRequest', { requestId, responseCode: 200,
          responseHeaders: [{ name: 'Content-Type', value: 'application/json' }, { name: 'Access-Control-Allow-Origin', value: origin }],
          body: Buffer.from(JSON.stringify(body)).toString('base64') });
      } else {
        await cdp('Fetch.fulfillRequest', { requestId, responseCode: 200,
          responseHeaders: [{ name: 'Content-Type', value: 'text/javascript' }],
          body: Buffer.from('window.PortOne={requestPayment:async c=>({paymentId:c.paymentId})};').toString('base64') });
      }
    }
  };
  await cdp('Page.enable'); await cdp('Runtime.enable');
  await cdp('Fetch.enable', { patterns: [{ urlPattern: '*api.sidey.app/api/commerce/*' }, { urlPattern: '*cdn.portone.io*' }] });
  const evaluate = async expression => (await cdp('Runtime.evaluate', { expression, returnByValue: true })).result.value;
  const waitFor = async expression => {
    for (let i = 0; i < 100; i++) { if (await evaluate(expression)) return; await pause(100); }
    throw new Error('Browser condition failed: ' + expression);
  };
  const capture = async name => {
    await pause(200);
    assert.equal(await evaluate('document.documentElement.scrollWidth <= window.innerWidth'), true, `${name}: horizontal overflow`);
    const { data } = await cdp('Page.captureScreenshot', { format: 'png' });
    await writeFile(`${output}/${name}.png`, Buffer.from(data, 'base64'));
  };
  for (const width of [1280, 390]) {
    await cdp('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: false });
    await cdp('Page.navigate', { url: `${origin}/SIDEY/checkout/#token=${token}` });
    await waitFor('document.querySelector("#checkout-product")?.hidden === false');
    assert.equal(await evaluate('location.hash'), '');
    await capture(`checkout-${width}`);
    await evaluate('document.querySelector("#checkout-consent").checked=true; document.querySelector("#checkout-consent").dispatchEvent(new Event("change")); document.querySelector("#checkout-pay").click();');
    await waitFor('document.querySelector("#result-title")?.textContent === "결제가 완료되었어요."');
    assert.equal(await evaluate('location.hash'), '');
    await capture(`result-${width}`);
    for (const locale of ['ko', 'en', 'ja']) {
      await cdp('Page.navigate', { url: `${origin}/SIDEY/${locale}/privacy/` });
      await waitFor('document.readyState === "complete" && !!document.querySelector("h1")');
      await capture(`privacy-${locale}-${width}`);
    }
  }
  assert.equal(requests, 6);
  unavailable = true;
  await cdp('Page.navigate', { url: `${origin}/SIDEY/checkout/#token=${token}` });
  await waitFor('document.querySelector("#checkout-error")?.hidden === false');
  assert.equal(await evaluate('document.querySelector("#checkout-error-message").textContent.includes("지금은 결제를")'), true);
  assert.equal(await evaluate('document.querySelector("#checkout-pay").disabled'), true);
  await capture('provider-unavailable');
  assert.equal(requests, 7);
  console.log(JSON.stringify({ output, viewports: [1280, 390], screenshots: 11, verifiedCheckoutRequests: requests, result: 'PASS' }));
} finally {
  socket?.close(); browser.kill('SIGTERM'); server.close();
}
