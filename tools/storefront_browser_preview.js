'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// Optional local visual QA. Requires Node 22+ and the installed Windows Edge.
// Wait for real application data; fixed virtual-time screenshots can capture
// an empty frame while Flutter/Firebase CDN assets are still loading.
module.exports = async function captureStorefrontBrowser() {
  const executable = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
  if (!fs.existsSync(executable)) throw Error('Installed Edge is required for optional browser screenshots.');
  const profile = path.resolve('build', 'edge-storefront-qa-' + Date.now());
  fs.mkdirSync(profile, {recursive:true});
  const browser = spawn(executable, ['--headless','--disable-gpu','--no-first-run','--remote-debugging-port=0','--user-data-dir=' + profile,'about:blank'], {windowsHide:true,stdio:['ignore','ignore','pipe']});
  let stderr = '';
  browser.stderr.on('data', value => { stderr += value.toString(); });
  let socket;
  let send;
  const errors = [];
  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let i=0;i<100 && !fs.existsSync(portFile);i++) await sleep(200);
    if (!fs.existsSync(portFile)) throw Error('Edge debug startup failed: ' + stderr.slice(-1000));
    const port = Number(fs.readFileSync(portFile,'utf8').split('\n')[0]);
    const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const target = targets.find(value => value.type === 'page');
    if (!target) throw Error('Edge did not open a test page.');
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve,reject) => { socket.onopen=resolve;socket.onerror=reject; });
    let sequence = 0;
    const pending = new Map();
    const requests = new Map();
    let responseStatus;
    send = (method,params={}) => new Promise((resolve,reject) => {
      const id = ++sequence;
      const timer = setTimeout(() => { pending.delete(id);reject(Error('Browser command timed out: '+method)); },15000);
      pending.set(id,{resolve,reject,timer});
      socket.send(JSON.stringify({id,method,params}));
    });
    socket.onmessage = event => {
      const message = JSON.parse(event.data);
      if (message.id) {
        const callback = pending.get(message.id);
        if (callback) { clearTimeout(callback.timer);pending.delete(message.id);message.error ? callback.reject(Error(message.error.message)) : callback.resolve(message.result); }
      } else if (message.method === 'Network.requestWillBeSent') requests.set(message.params.requestId,message.params.request.url);
      else if (message.method === 'Network.responseReceived' && requests.get(message.params.requestId)?.includes('/getPublicStorefront') && message.params.response.status !== 204) responseStatus = message.params.response.status;
      else if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.exception?.description || message.params.exceptionDetails.text);
    };
    socket.onclose = () => { for (const callback of pending.values()) { clearTimeout(callback.timer);callback.reject(Error('Browser closed.')); } pending.clear(); };
    await send('Runtime.enable');await send('Network.enable');await send('Page.enable');
    await send('Page.navigate',{url:'http://127.0.0.1:5000/b/karachi-table'});
    for (let i=0;i<120 && responseStatus === undefined;i++) await sleep(1000);
    if (responseStatus !== 200 || errors.length) {
      fs.writeFileSync('build/storefront-browser-errors.json',JSON.stringify({responseStatus,errors,requests:[...requests.values()],stderr},null,2));
      throw Error('Browser storefront did not load: status=' + responseStatus + '; ' + errors.join('; ').slice(0,1000));
    }
    await sleep(2000);
    for (const [label,width,height] of [['desktop',1440,1000],['mobile',390,844]]) {
      await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:label==='mobile'});
      await sleep(1500);
      const screenshot = await send('Page.captureScreenshot',{format:'png'});
      const output = path.resolve('build','storefront-' + label + '.png');
      fs.writeFileSync(output,Buffer.from(screenshot.data,'base64'));
      console.log('Saved ready storefront screenshot: ' + output);
    }
    console.log('PASS: Compiled browser storefront loaded through the anonymous callable without JavaScript exceptions.');
  } finally {
    if (send && socket?.readyState===WebSocket.OPEN) await Promise.race([send('Browser.close').catch(()=>{}),sleep(2000)]);
    socket?.close();
    if (browser.exitCode===null) browser.kill();
  }
};
