// Cra's scriptlets (Resources/blocklist/scriptlets.js) on stand-ins for YouTube's and X's data (#845).
// Run by scripts/test.sh; the scenario filter-page-scripts and CraCore ScriptletsTests lock #845.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
// Values from the page's realm, compared as data.
const plain = v => JSON.parse(JSON.stringify(v));
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../resources/blocklist/scriptlets.js'), 'utf8');

// CraCore ScriptletTable.json's format: {host: [[name, args…]]} and the rest as its lines.
function encode(calls, exceptions, excluded, paused) {
    const index = new Map();
    let h = '\n', r = '\n', x = '\n', e = '\n';
    for (const host of Object.keys(calls).sort()) {
        const numbers = [];
        for (const call of calls[host]) {
            const key = JSON.stringify(call);
            if (!index.has(key)) { index.set(key, index.size); r += index.get(key) + '\t' + key + '\n'; }
            const i = index.get(key);
            numbers.push(i);
            const out = excluded[host] && excluded[host][call.join('\u001f')];
            if (out) e += host + '\t' + i + '\t' + JSON.stringify(out) + '\n';
        }
        h += host + '\t' + numbers.join(',') + '\n';
    }
    for (const host of Object.keys(exceptions)) x += host + '\t' + JSON.stringify(exceptions[host]) + '\n';
    return { h, r, x, e, p: paused };
}

// A page's global on `host` with the table's calls run; `responses` answers its fetch and XHR by URL.
function page(host, calls, { exceptions = {}, excluded = {}, paused = [], responses = {} } = {}) {
    const requests = [];
    class FakeXHR {
        open(method, url) { this._url = url; }
        send() {
            requests.push(this._url);
            this.readyState = 4;
            this._text = responses[this._url] || '';
        }
        dispatchEvent() {}
    }
    Object.defineProperty(FakeXHR.prototype, 'responseText', { configurable: true, get() { return this._text; } });
    Object.defineProperty(FakeXHR.prototype, 'response', { configurable: true, get() { return this.responseType === 'json' ? JSON.parse(this._text) : this._text; } });
    FakeXHR.prototype.responseType = '';
    // Its own Response, so one page's wrapped Response.prototype.json stays its own.
    const PageResponse = class extends Response {};
    const context = vm.createContext({
        location: { hostname: host, href: 'https://' + host + '/', pathname: '/', search: '' },
        URL, Response: PageResponse, WeakMap, Promise, setTimeout, Event: class {}, XMLHttpRequest: FakeXHR,
        fetch: async url => { requests.push(String(url)); return new PageResponse(responses[String(url)] || '{}'); },
    });
    const table = encode(calls, exceptions, excluded, paused);
    vm.runInContext('(' + source + ')(' + JSON.stringify(table) + ', globalThis)', context);
    context.requests = requests;
    return context;
}

const ytResponse = JSON.stringify({
    playerResponse: { adPlacements: [{ ad: 1 }], playerAds: [{ ad: 2 }], videoDetails: { videoId: 'v' } },
    adSlots: [1], streamingData: { formats: [] },
});

test('json-prune takes YouTube’s ads out of the player data the page parses', () => {
    const g = page('www.youtube.com', {
        'youtube.com': [['json-prune', 'playerResponse.adPlacements playerResponse.playerAds adPlacements playerAds adSlots']],
    });
    const parsed = vm.runInContext('JSON.parse(' + JSON.stringify(ytResponse) + ')', g);
    assert.equal(parsed.playerResponse.adPlacements, undefined);
    assert.equal(parsed.playerResponse.playerAds, undefined);
    assert.equal(parsed.adSlots, undefined);
    assert.equal(parsed.playerResponse.videoDetails.videoId, 'v');
    assert.equal(vm.runInContext('JSON.parse.toString().includes("native code")', g), true);
});

test('set-constant keeps ytInitialPlayerResponse.adPlacements undefined when the page sets it', () => {
    const g = page('www.youtube.com', { 'youtube.com': [['set-constant', 'ytInitialPlayerResponse.adPlacements', 'undefined']] });
    vm.runInContext('globalThis.ytInitialPlayerResponse = { adPlacements: [1], videoDetails: { videoId: "v" } }', g);
    assert.equal(vm.runInContext('ytInitialPlayerResponse.adPlacements', g), undefined);
    assert.equal(vm.runInContext('ytInitialPlayerResponse.videoDetails.videoId', g), 'v');
});

test('json-prune-fetch-response prunes only the requests it names', async () => {
    const player = 'https://www.youtube.com/youtubei/v1/player?key=1';
    const other = 'https://www.youtube.com/youtubei/v1/next';
    const g = page('www.youtube.com', {
        'www.youtube.com': [['json-prune-fetch-response', 'adPlacements adSlots playerResponse.adPlacements', '', 'propsToMatch', '/\\/player(\\?|$)/']],
    }, { responses: { [player]: ytResponse, [other]: ytResponse } });
    const pruned = await vm.runInContext('fetch(' + JSON.stringify(player) + ').then(r => r.json())', g);
    assert.equal(pruned.playerResponse.adPlacements, undefined);
    assert.equal(pruned.adSlots, undefined);
    const left = await vm.runInContext('fetch(' + JSON.stringify(other) + ').then(r => r.json())', g);
    assert.equal(left.adSlots.length, 1);
});

test('trusted-replace-xhr-response rewrites the player response text (uBlock filters’ own YouTube rule)', () => {
    const player = 'https://www.youtube.com/youtubei/v1/player';
    // www.youtube.com##+js(trusted-replace-xhr-response, /"adPlacements.*?([A-Z]"\}|"\}{2\,4})\}\]\,/, , /playlist\?list=|\/player(?:\?.+)?$|watch\?[tv]=/)
    const g = page('www.youtube.com', {
        'www.youtube.com': [['trusted-replace-xhr-response', '/"adPlacements.*?([A-Z]"\\}|"\\}{2,4})\\}\\],/', '', '/playlist\\?list=|\\/player(?:\\?.+)?$|watch\\?[tv]=/']],
    }, { responses: { [player]: '{"adPlacements":[{"r":{"k":"X"}}],"videoId":"v"}' } });
    const text = vm.runInContext('(() => { const x = new XMLHttpRequest(); x.open("GET", ' + JSON.stringify(player) + '); x.send(); return x.responseText; })()', g);
    assert.equal(text, '{"videoId":"v"}');
});

const timeline = () => JSON.stringify({
    data: { home: { home_timeline_urt: { instructions: [{ entries: [
        { entryId: 'tweet-1', content: { content: { tweet: 1 } } },
        { entryId: 'promoted-2', content: { content: { promoted_metadata: { advertiser: 'x' } } } },
        { entryId: 'tweet-3', content: { content: { tweet: 3 } } },
    ] }] } } },
});

test('json-prune takes X’s promoted posts out of the timeline (uBlock Origin’s [-] path)', () => {
    const g = page('x.com', {
        'x.com': [['json-prune', 'data.*.home_timeline_urt.instructions.*.entries.[-].content.content.promoted_metadata']],
    });
    const parsed = vm.runInContext('JSON.parse(' + JSON.stringify(timeline()) + ')', g);
    assert.deepEqual(plain(parsed.data.home.home_timeline_urt.instructions[0].entries.map(e => e.entryId)), ['tweet-1', 'tweet-3']);
});

test('json-prune takes X’s promoted posts out of the timeline (JSONPath)', () => {
    const g = page('x.com', { 'x.com': [['json-prune', '$.data..["entries","items"][?(@.*.content.promoted_metadata)]']] });
    const parsed = vm.runInContext('JSON.parse(' + JSON.stringify(timeline()) + ')', g);
    assert.deepEqual(plain(parsed.data.home.home_timeline_urt.instructions[0].entries.map(e => e.entryId)), ['tweet-1', 'tweet-3']);
});

test('trusted-edit-inbound-object edits what the page sends, as uBlock filters asks for YouTube', () => {
    const g = page('www.youtube.com', { 'www.youtube.com': [['trusted-edit-inbound-object', 'JSON.stringify', '0',
        '[?.attestationRequest][?.context.client.userAgent*="channel"].context.client[?.clientName=="WEB"]+={"clientScreen":"CHANNEL"}']] });
    const sent = JSON.parse(vm.runInContext('JSON.stringify({ attestationRequest: {}, context: { client: { clientName: "WEB", userAgent: "Mozilla; channel" } } })', g));
    assert.equal(sent.context.client.clientScreen, 'CHANNEL');
    const other = JSON.parse(vm.runInContext('JSON.stringify({ context: { client: { clientName: "WEB", userAgent: "channel" } } })', g));
    assert.equal(other.context.client.clientScreen, undefined);
});

test('a site’s exception, an excluded subdomain and a paused site run nothing', () => {
    const call = ['json-prune', 'adSlots'];
    const key = call.join('\u001f');
    const run = (host, options) => plain(vm.runInContext('JSON.parse(\'{"adSlots":[1]}\').adSlots', page(host, { 'example.com': [call] }, options)) ?? null);
    assert.equal(run('www.example.com'), null);
    assert.deepEqual(run('www.example.com', { exceptions: { 'www.example.com': [key] } }), [1]);
    assert.deepEqual(run('www.example.com', { exceptions: { 'example.com': [''] } }), [1]);
    assert.deepEqual(run('a.example.com', { excluded: { 'example.com': { [key]: ['a.example.com'] } } }), [1]);
    assert.deepEqual(run('www.example.com', { paused: ['www.example.com'] }), [1]);
    assert.deepEqual(plain(vm.runInContext('JSON.parse(\'{"adSlots":[1]}\').adSlots', page('other.org', { 'example.com': [call] }))), [1]);
});

test('abort-on-property-read stops a script that reads the property, and the page sees no error', () => {
    const g = page('ads.example', { 'ads.example': [['abort-on-property-read', 'adLoader.start']] });
    assert.throws(() => vm.runInContext('adLoader.start', g));
    vm.runInContext('globalThis.adLoader = { start: 1 }', g);
    assert.throws(() => vm.runInContext('adLoader.start', g));
});

test('an entity rule (site.*) runs on any top-level domain', () => {
    const g = page('www.example.co', { 'example.*': [['json-prune', 'adSlots']] });
    assert.equal(vm.runInContext('JSON.parse(\'{"adSlots":[1]}\').adSlots', g), undefined);
});

test('no-fetch-if answers a request it stops without sending it', async () => {
    const g = page('news.example', { 'news.example': [['no-fetch-if', 'pagead2']] });
    const text = await vm.runInContext('fetch("https://pagead2.googlesyndication.com/x").then(r => r.text())', g);
    assert.equal(text, '');
    assert.equal(g.requests.length, 0);
});

test('several set-constant rules under one object all hold, as uBlock filters sets YouTube’s three', () => {
    const calls = ['playerAds', 'adPlacements', 'adSlots'].map(k => ['set-constant', 'ytInitialPlayerResponse.' + k, 'undefined']);
    const g = page('www.youtube.com', { 'www.youtube.com': calls });
    vm.runInContext('globalThis.ytInitialPlayerResponse = { playerAds: [1], adPlacements: [2], adSlots: [3], videoDetails: { videoId: "v" } }', g);
    assert.equal(vm.runInContext('[ytInitialPlayerResponse.playerAds, ytInitialPlayerResponse.adPlacements, ytInitialPlayerResponse.adSlots].join("|")', g), '||');
    assert.equal(vm.runInContext('ytInitialPlayerResponse.videoDetails.videoId', g), 'v');
});
