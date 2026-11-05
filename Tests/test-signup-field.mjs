// Run with node Tests/test-signup-field.mjs (Node 22+). CHROME may point to another Chromium executable.
// Drive trusted input via DevTools in a fresh profile. Script-generated focus/click is deliberately inert.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';

const script = await readFile(new URL('../resources/web/signup-email.js', import.meta.url), 'utf8');
const fixture = await readFile(new URL('Fixtures/Pages/signup-email.html', import.meta.url));
const executable = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const profile = await mkdtemp(join(tmpdir(), 'cra-signup-'));
const server = createServer((_, res) => { res.writeHead(200, {'Content-Type':'text/html'}); res.end(fixture); });
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = 'http://127.0.0.1:' + server.address().port;
const browser = spawn(executable, ['--headless', '--no-first-run', '--disable-extensions', '--disable-background-networking',
  '--window-size=1100,900', '--remote-debugging-port=0', '--user-data-dir=' + profile, origin], {stdio:'ignore'});
let socket;
async function until(operation) {
  for (let attempt = 0; attempt < 60; attempt++) {
    const value = await operation();
    if (value) return value;
    await delay(50);
  }
  throw new Error('Timed out waiting for Chromium');
}
try {
  const port = await until(() => readFile(join(profile, 'DevToolsActivePort'), 'utf8').then(s => s.split('\n')[0], () => null));
  const targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
  socket = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(resolve => socket.onopen = resolve);
  let serial = 0, world;
  const pending = new Map(), events = [];
  socket.onmessage = ({data}) => {
    const reply = JSON.parse(data);
    if (reply.id) { pending.get(reply.id)(reply); pending.delete(reply.id); }
    if (reply.method === 'Runtime.bindingCalled' && reply.params.name === 'craSignupField') {
      events.push(reply.params.payload ? JSON.parse(reply.params.payload) : null);
    }
  };
  const call = (method, params = {}) => new Promise(resolve => {
    const id = ++serial;
    pending.set(id, resolve);
    socket.send(JSON.stringify({id, method, params}));
  });
  async function evaluate(expression, contextId) {
    const {result, error} = await call('Runtime.evaluate', {expression, contextId, returnByValue:true});
    assert(!error, error?.message);
    assert(!result.exceptionDetails, result.result.description);
    return result.result.value;
  }
  const isolated = (name, ...args) => evaluate('window.__cra.' + name + '(' + args.map(x => JSON.stringify(x)).join(',') + ')', world);
  async function tap(id) {
    const {x, y} = await evaluate(`(() => { const field = document.getElementById(${JSON.stringify(id)}); field.scrollIntoView({block:"nearest"}); const r = field.getBoundingClientRect();
      return {x:r.x+r.width/2, y:r.y+r.height/2}; })()`);
    await delay(50); // Deliver any scroll event before the click a human would make.
    for (const type of ['mousePressed', 'mouseReleased']) {
      await call('Input.dispatchMouseEvent', {type, x, y, button:'left', clickCount:1});
    }
    await delay(240);
  }
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Runtime.addBinding', {name:'craSignupField', executionContextName:'cra'});
  await call('Page.addScriptToEvaluateOnNewDocument', {source:'window.__cra = {};\n' + script, worldName:'cra', runImmediately:true});
  async function visit(path) {
    await call('Page.navigate', {url:origin + path});
    await until(() => evaluate('location.pathname === ' + JSON.stringify(path) + ' && !!document.getElementById("email")'));
    const frameId = (await call('Page.getFrameTree')).result.frameTree.frame.id;
    world = (await call('Page.createIsolatedWorld', {frameId, worldName:'cra'})).result.executionContextId;
  }
  await visit('/start');
  assert.equal(await evaluate('typeof window.craSignupField'), 'undefined');
  await evaluate('email.focus(); email.click()');
  await delay(180);
  assert.equal(events.length, 0, 'The page cannot trigger the native offer');

  await tap('email');
  const initial = events.at(-1);
  assert.equal(initial.url, origin);
  assert.match(initial.hints, /email example/);
  assert(!initial.hints.includes('user@example.com'));
  assert(await isolated('signupMatches', initial.token));
  await evaluate('email.value = "manual"');
  assert.equal(await isolated('signupFill', initial.token, 'test@example.com'), false);
  assert.equal(await evaluate('email.value'), 'manual');

  await evaluate('email.value = ""');
  await tap('email');
  const original = events.at(-1);
  assert.notEqual(original.token, initial.token);
  const countBeforeReflow = events.length;
  await evaluate('signup.style.transform = "translateY(2px)"');
  await call('Emulation.setDeviceMetricsOverride', {width:original.viewportWidth + 2, height:original.viewportHeight + 1,
    deviceScaleFactor:1, mobile:false});
  await delay(200);
  assert(await isolated('signupMatches', original.token), 'A tiny viewport/field correction preserves the button');
  assert.equal(events.length, countBeforeReflow);

  await evaluate('signup.style.paddingTop = "48px"');
  assert.equal(await isolated('signupMatches', original.token), false);
  await until(() => events.at(-1)?.token && events.at(-1).token !== original.token);
  const moved = events.at(-1);
  assert(moved.y > original.y + 30, 'The same focused field publishes its settled new position');
  assert.equal(await isolated('signupFill', original.token, 'test@example.com'), false);
  assert.equal(await evaluate('email.value'), '');

  // A native Escape for the last visible token can arrive while re-anchoring.
  await evaluate('signup.style.paddingTop = "70px"');
  assert.equal(await isolated('signupMatches', moved.token), false);
  assert(await isolated('signupDismiss', moved.token));
  const cancelled = events.length;
  await evaluate('signup.style.paddingTop = "10px"');
  await delay(240);
  assert.equal(events.length, cancelled, 'A dismissed re-anchor cannot snap back');
  await tap('email');
  assert.equal(await isolated('signupDismiss', moved.token), false, 'An older Escape cannot cancel a new click');
  assert(await isolated('signupFill', events.at(-1).token, 'test@example.com'));
  assert.deepEqual(await evaluate('[email.value, changes, submits]'), ['test@example.com', ['input:email','change:email'], 0]);

  for (const id of ['code', 'password', 'invite', 'news', 'login']) {
    const count = events.length;
    await tap(id);
    assert.equal(events.length, count, id + ' must not trigger signup fill');
  }
  await evaluate('email.value = ""; code.focus()');
  for (const type of ['rawKeyDown','keyUp']) {
    await call('Input.dispatchKeyEvent', {type, key:'Tab', code:'Tab', modifiers:8, windowsVirtualKeyCode:9});
  }
  await until(() => !!events.at(-1)?.token);
  assert.equal(await evaluate('document.activeElement.id'), 'email', 'Tab navigation can trigger a field offer');
  await call('Input.insertText', {text:'q'});
  await until(() => events.at(-1) === null);
  assert.equal(await evaluate('email.value'), 'q', 'Typing dismisses and continues ordinarily');

  const embedded = await evaluate(`(() => {
    const frame = document.querySelector('iframe'); frame.scrollIntoView({block:'center'}); const r = frame.getBoundingClientRect();
    const field = frame.contentDocument.querySelector('input').getBoundingClientRect();
    return {x:r.x+frame.clientLeft+field.x+12, y:r.y+frame.clientTop+field.y+5}; })()`);
  const beforeFrame = events.length;
  for (const type of ['mousePressed','mouseReleased']) {
    await call('Input.dispatchMouseEvent', {type, ...embedded, button:'left', clickCount:1});
  }
  await delay(220);
  assert.equal(await evaluate('document.activeElement.tagName'), 'IFRAME');
  assert.equal(events.length, beforeFrame, 'Embedded forms cannot open a native offer');

  await evaluate('email.value = ""');
  await tap('email');
  const previous = events.at(-1).token;
  // Bitwarden mounts a fixed iframe inside a closed shadow in a manual popover. The
  // host itself is zero-sized. A button inside the field must leave Cra usable, while
  // the provider list covering the area beside it takes precedence.
  await evaluate(`(() => {
    const r = email.getBoundingClientRect(), host = document.createElement('div');
    host.id = 'provider'; host.popover = 'manual';
    host.style = 'position:fixed;inset:auto;margin:0;border:0;padding:0;overflow:visible;width:0;height:0';
    const frame = window.providerFrame = document.createElement('iframe');
    frame.style = 'position:fixed;border:0;left:' + (r.right-22) + 'px;top:' + (r.y+3) + 'px;width:18px;height:18px';
    host.attachShadow({mode:'closed'}).append(frame);
    document.body.append(host); host.showPopover();
  })()`);
  await delay(240);
  assert(await isolated('signupMatches', previous), 'An in-field provider icon is compatible');
  await evaluate(`(() => { provider.hidePopover(); const r=email.getBoundingClientRect();
    Object.assign(providerFrame.style,{left:r.left+'px',top:r.bottom+'px',width:'200px',height:'60px'}); provider.showPopover(); })()`);
  await until(() => events.at(-1) === null);
  assert.equal(await isolated('signupMatches', previous), false, 'An open provider menu wins');
  await evaluate('provider.remove()');
  await tap('email');
  await call('Input.dispatchKeyEvent', {type:'rawKeyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
  await call('Input.dispatchKeyEvent', {type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
  await until(() => events.at(-1) === null);
  await tap('email');
  assert(events.at(-1)?.token, 'A second click can reopen it');
  await isolated('signupConfigure', false, 20);
  const disabled = events.length;
  await isolated('signupConfigure', true, 19);
  await tap('email');
  assert.equal(events.length, disabled, 'A late activation cannot reenable the preference');
  await isolated('signupConfigure', true, 21);
  await tap('email');
  const stale = events.at(-1).token;
  await visit('/second');
  assert.equal(await isolated('signupFill', stale, 'test@example.com'), false);
  await tap('email');
  assert.notEqual(events.at(-1).token, stale, 'A new document can offer its own field');
  console.log('Signup field interactions passed');
} finally {
  socket?.close();
  const closed = new Promise(resolve => browser.once('close', resolve));
  browser.kill();
  await closed;
  await rm(profile, {recursive:true, force:true});
  await new Promise(resolve => server.close(resolve));
}
