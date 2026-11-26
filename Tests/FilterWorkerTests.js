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
    const state = { dynamic: [previous], session: [pause('first.example')], cache: {}, replies: [] };
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

for (const stage of ['session', 'dynamic']) {
    test('retains previous filters and retries after failure updating ' + stage, async () => {
        const state = worker();
        state.fail = stage;
        assert.deepEqual(await state.apply('next'), { failed: 'next' });
        assert.deepEqual(state.dynamic, [previous]);
        assert.deepEqual(state.session, [pause('first.example')]);
        assert.deepEqual(state.cache, {});
        delete state.fail;
        assert.deepEqual(await state.apply('next'), { applied: 'next' });
        assert.deepEqual(state.dynamic, [loaderRule]);
        assert.deepEqual(state.session, [pause('new.example')]);
    });
}

test('empty selection and cached acknowledgement after a failed replacement', async () => {
    const state = worker();
    await state.apply('first');
    state.fail = 'dynamic';
    assert.deepEqual(await state.apply('empty', [], []), { failed: 'empty' });
    delete state.fail;
    await state.apply('empty', [], []);
    assert.deepEqual([state.dynamic, state.session], [[], []]);
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
    assert.deepEqual([state.dynamic, state.session], [[], []]);
    assert.equal(state.cache.appliedFilterRevision, 'second');
});
