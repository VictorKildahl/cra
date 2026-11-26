const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../resources/blocklist/chromium/filters.js'), 'utf8');
const previous = { id: 2 };
const pause = host => ({ id: 3, condition: { requestDomains: [host] } });
const loaderRule = { id: 1, action: { type: 'block' }, condition: { requestDomains: ['html-load.com'] } };

function worker() {
    const state = { dynamic: [previous], session: [pause('first.example')], scripts: [], cache: {}, replies: [] };
    let receive;
    const event = { addListener() {} };
    const port = {
        onMessage: { addListener(fn) { receive = fn; } }, onDisconnect: event,
        postMessage(message) { state.replies.push(structuredClone(message)); },
    };
    function update(key, value) {
        if (state.fail === key) throw Error('simulated ' + key);
        state[key] = structuredClone(value);
    }
    const runtime = vm.createContext({
        console: { error() {}, warn() {} }, TextDecoder, atob, chrome: {
            runtime: { connectNative: () => port, onStartup: event, onInstalled: event },
            alarms: { onAlarm: event },
            scripting: {
                getRegisteredContentScripts: async () => state.scripts,
                registerContentScripts: async next => update('scripts', next),
                unregisterContentScripts: async () => update('scripts', []),
                updateContentScripts: async ([next]) => update('scripts', [{ ...state.scripts[0], ...next }]),
            },
            declarativeNetRequest: {
                getDynamicRules: async () => state.dynamic, getSessionRules: async () => state.session,
                updateDynamicRules: async next => update('dynamic', next.addRules),
                updateSessionRules: async next => update('session', next.addRules),
            },
            storage: { session: {
                get: async () => state.cache, remove: async key => { delete state.cache[key]; },
                set: async fields => update('cache', fields),
            } },
        },
    });
    vm.runInContext(source, runtime);
    state.apply = async (revision, rules = [loaderRule], siteExceptions = [pause('new.example')]) => {
        receive({ revision });
        const payload = Buffer.from(JSON.stringify({ revision, rules, siteExceptions }));
        receive({ id: revision, chunk: payload.toString('base64') });
        receive({ id: revision, done: true });
        await vm.runInContext('updates', runtime);
        return state.replies.at(-1);
    };
    return state;
}

for (const stage of ['scripts', 'session', 'dynamic']) {
    test('retains previous filters and retries after failure updating ' + stage, async () => {
        const state = worker();
        state.fail = stage;
        assert.deepEqual(await state.apply('next'), { failed: 'next' });
        assert.deepEqual(state.dynamic, [previous]);
        assert.deepEqual(state.session, [pause('first.example')]);
        assert.deepEqual(state.scripts, []);
        assert.deepEqual(state.cache, {});
        delete state.fail;
        assert.deepEqual(await state.apply('next'), { applied: 'next' });
        assert.deepEqual(state.dynamic, [loaderRule]);
        assert.deepEqual(state.session, [pause('new.example')]);
        assert.deepEqual(state.scripts[0].excludeMatches, ['*://new.example/*']);
    });
}

test('empty selection and cached acknowledgement after a failed replacement', async () => {
    const state = worker();
    await state.apply('first');
    state.fail = 'dynamic';
    assert.deepEqual(await state.apply('empty', [], []), { failed: 'empty' });
    assert.deepEqual(state.scripts[0].excludeMatches, ['*://new.example/*']);
    delete state.fail;
    await state.apply('empty', [], []);
    assert.deepEqual([state.dynamic, state.session, state.scripts], [[], [], []]);
    state.fail = 'dynamic';
    assert.deepEqual(await state.apply('empty', [], []), { applied: 'empty' });
});

test('a cache failure reports the applied revision and allows reconciliation', async () => {
    const state = worker();
    state.fail = 'cache';
    assert.deepEqual(await state.apply('next'), { applied: 'next' });
    assert.deepEqual(state.cache, {});
    delete state.fail;
    await state.apply('next');
    assert.equal(state.cache.appliedFilterRevision, 'next');
});

test('a newer queued revision supersedes an earlier selection', async () => {
    const state = worker();
    const first = state.apply('first');
    const second = state.apply('second', [], []);
    await Promise.all([first, second]);
    assert.deepEqual(state.replies, [{ applied: 'second' }]);
    assert.deepEqual([state.dynamic, state.session, state.scripts], [[], [], []]);
    assert.equal(state.cache.appliedFilterRevision, 'second');
});

test('failed update of an existing registration restores its exact host exclusions', async () => {
    const state = worker();
    await state.apply('first');
    state.fail = 'dynamic';
    assert.deepEqual(await state.apply('second', [loaderRule], [pause('second.example')]), { failed: 'second' });
    assert.deepEqual(state.scripts[0].excludeMatches, ['*://new.example/*']);
    assert.deepEqual(state.session, [pause('new.example')]);
    delete state.fail;
    await state.apply('second', [loaderRule], [pause('second.example')]);
    assert.deepEqual(state.scripts[0].excludeMatches, ['*://second.example/*']);
});

test('an allow rule with only excluded initiators keeps recovery on those sites', async () => {
    const state = worker();
    const except = (...domains) => ({
        id: 4, action: { type: 'allow' },
        condition: { requestDomains: ['html-load.com'], excludedInitiatorDomains: domains },
    });
    await state.apply('global');
    await state.apply('limited', [except('news.example', 'press.example'), loaderRule, except('local.news.example', 'press.example')]);
    assert.deepEqual(state.scripts[0].matches, ['*://*.local.news.example/*', '*://*.press.example/*']);
    state.fail = 'dynamic';
    assert.deepEqual(await state.apply('global-again'), { failed: 'global-again' });
    assert.deepEqual(state.scripts[0].matches, ['*://*.local.news.example/*', '*://*.press.example/*']);
    delete state.fail;
    await state.apply('allow-everywhere', [loaderRule, except()]);
    assert.deepEqual(state.scripts, []);
});

test('a document exception excludes the site and its subdomains from recovery', async () => {
    const state = worker();
    const allowPage = condition => ({ id: 4, action: { type: 'allowAllRequests' },
        condition: { resourceTypes: ['main_frame', 'sub_frame'], ...condition } });
    await state.apply('before', [loaderRule], []);
    await state.apply('except-news', [allowPage({requestDomains: ['news.example']}), loaderRule], []);
    assert.deepEqual(state.scripts[0].matches, ['http://*/*', 'https://*/*']);
    assert.deepEqual(state.scripts[0].excludeMatches, ['*://*.news.example/*']);
    await state.apply('unbounded', [loaderRule, allowPage({urlFilter: '/preview/'})], []);
    assert.deepEqual(state.scripts, []);
    await state.apply('removed', [loaderRule], []);
    assert.deepEqual(state.scripts[0].excludeMatches, []);
});
