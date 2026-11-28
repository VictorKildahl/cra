// Run with node --test Tests/AdShieldRecoveryTests.js.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const resources = path.join(__dirname, '../resources/blocklist/chromium');
const recovery = fs.readFileSync(path.join(resources, 'adshield.js'), 'utf8');
const source = '{"sequence":90071992547409931,"ads":{"adShieldEnabled":true,"adBlockWallEnabled":true}}';

function page({ url = 'https://html-load.com/sdk.js', sdk = true, json = source } = {}) {
    class Script {
        src = url;
        onerror = true;
        matches() { return sdk && this.onerror; }
        removeAttribute(name) { assert.equal(name, 'onerror'); this.onerror = false; }
    }
    const loader = new Script();
    const data = { textContent: json };
    const events = {};
    const document = {
        readyState: 'interactive',
        addEventListener(name, callback) { events[name] = callback; },
        querySelectorAll(selector) { return selector.includes('application/json') ? [data] : [loader]; },
    };
    vm.runInNewContext(recovery, { window: document, document, HTMLScriptElement: Script });
    return { data, loader, events };
}

test('the JSON change precedes a late SDK error and preserves other fields byte for byte', () => {
    const { data, loader, events } = page();
    events.readystatechange();
    assert.equal(data.textContent, source.replace('"adBlockWallEnabled":true', '"adBlockWallEnabled":false'));
    events.error({ target: loader, isTrusted: true });
    assert.equal(loader.onerror, false);
});

test('an early error still identifies the SDK after its onerror attribute is removed', () => {
    const { data, loader, events } = page();
    events.error({ target: loader, isTrusted: true });
    events.readystatechange();
    assert.equal(JSON.parse(data.textContent).ads.adBlockWallEnabled, false);
});

test('other origins, ordinary scripts and synthetic errors keep their callbacks', () => {
    for (const options of [{ url: 'https://html-load.com.example/sdk.js' }, { sdk: false }]) {
        const { data, loader, events } = page(options);
        events.error({ target: loader, isTrusted: true });
        events.readystatechange();
        assert.equal(loader.onerror, true);
        assert.equal(data.textContent, source);
    }
    const { loader, events } = page();
    events.error({ target: loader, isTrusted: false });
    assert.equal(loader.onerror, true);
});

test('malformed, unrelated and ambiguous page data is preserved', () => {
    for (const json of ['{', '{"adBlockWallEnabled":true}', source.replace('"adShieldEnabled":true', '"adShieldEnabled":false'),
        source.replace('"sequence":', '"adBlockWallEnabled":true,"sequence":')]) {
        const { data, events } = page({ json });
        events.readystatechange();
        assert.equal(data.textContent, json);
    }
});
