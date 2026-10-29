// Exercise the actual cleanup expression against isolated extension contexts. A URL
// match alone must never close a normal extension tab, even after its owner changes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const expression = fs.readFileSync(process.argv[2], 'utf8');

function check({popup, host = 'testextension', api = true}, shouldClose) {
  let closed = 0;
  const window = {close() { closed++; }};
  const context = {
    window,
    location: {protocol: 'chrome-extension:', hostname: host},
    chrome: api ? {extension: {getViews({type}) {
      assert.equal(type, 'popup');
      return popup ? [window] : [];
    }}} : undefined,
  };
  const result = vm.runInNewContext(expression, context, {timeout: 1000});
  assert.equal(result, shouldClose);
  assert.equal(closed, shouldClose ? 1 : 0);
}

check({popup: true}, true); // Owner/tab invalidated: its verified popup closes itself.
check({popup: false}, false); // Same URL in a normal extension tab stays open.
check({popup: true, host: 'otherextension'}, false);
check({popup: true, api: false}, false); // Missing verification fails closed.
console.log('Extension popup cancellation: 4 checks passed');
