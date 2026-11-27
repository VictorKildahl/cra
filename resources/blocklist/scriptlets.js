// Cra's scriptlets (#845). Copyright Cra contributors, MIT License (written for Cra; it shares only the
// scriptlets' names and argument conventions with the filter lists that call them).
//
// Runs in every frame's main world before the page's own scripts. Cra calls it with the table of the lists in use
// (CraCore ScriptletTable.json): strings of lines it looks up for the frame's host alone, so a table naming
// thousands of sites costs a frame a few searches, not a parse of all of it:
//   h "\n<host>\t<i>,<j>\n"  r "\n<i>\t<[name, args…]>\n"  x "\n<host>\t<[exception keys]>\n"
//   e "\n<host>\t<i>\t<[excluded hosts]>\n"  p [paused hosts]
// It runs the calls for the frame's host, each on its own, so one failing leaves the rest.
(function craScriptlets(table, scope) {
    'use strict';
    if (!table || typeof table !== 'object' || typeof table.h !== 'string') return;
    const win = scope;
    const loc = win.location;
    const host = String(loc && loc.hostname || '').toLowerCase();
    if (!host || (table.p || []).includes(host)) return;

    // What the page can't change under us: taken before its first line runs.
    const { Object: O, Reflect: R, JSON: J, Proxy: P, RegExp: RE, Array: A, String: S } = win;
    const jsonParse = J.parse.bind(J);
    const jsonStringify = J.stringify.bind(J);
    const defineProperty = O.defineProperty;
    const getOwnDescriptor = O.getOwnPropertyDescriptor;
    const apply = R.apply;
    const ownKeys = R.ownKeys;

    // The text after "\n<key>\t" up to the line's end, or null.
    const lookup = (text, key) => {
        if (typeof text !== 'string') return null;
        const at = text.indexOf('\n' + key + '\t');
        if (at < 0) return null;
        const start = at + key.length + 2;
        return text.slice(start, text.indexOf('\n', start));
    };

    // The keys of the host, as ScriptletTable.keys: each parent, each also as `label.*`, then "".
    const keys = [];
    const labels = host.split('.');
    while (labels.length) {
        keys.push(labels.join('.'));
        if (labels.length >= 2) keys.push(labels.slice(0, -1).join('.') + '.*');
        labels.shift();
    }
    keys.push('');
    const off = new Set();
    for (const k of keys) {
        const line = lookup(table.x, k);
        if (line) { try { for (const x of jsonParse(line)) off.add(x); } catch (_) {} }
    }
    if (off.has('')) return;
    const calls = [];
    const seen = new Set();
    for (const k of keys) {
        const line = lookup(table.h, k);
        if (!line) continue;
        for (const n of line.split(',')) {
            if (seen.has(n)) continue;
            seen.add(n);
            let call;
            try { call = jsonParse(lookup(table.r, n)); } catch (_) { continue; }
            if (!A.isArray(call) || off.has(call.join('\u001f'))) continue;
            const excluded = lookup(table.e, k + '\t' + n);
            if (excluded) { try { if (jsonParse(excluded).some(h => keys.includes(h))) continue; } catch (_) {} }
            calls.push(call);
        }
    }
    if (!calls.length) return;

    // ---- Helpers -----------------------------------------------------------------------------------------------

    // `/re/flags` a regular expression, '' anything, else the text itself; a leading '!' (where a scriptlet allows
    // it) is handled by the caller.
    function pattern(text, flags) {
        text = S(text == null ? '' : text);
        if (text === '' || text === '*') return /^/;
        const m = /^\/(.+)\/([gimsu]*)$/.exec(text);
        if (m) {
            try { return new RE(m[1], flags != null ? flags : m[2]); } catch (_) { return /(?!)/; }
        }
        return new RE(text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags || '');
    }
    function needle(text) {
        text = S(text == null ? '' : text);
        const not = text.startsWith('!');
        const re = pattern(not ? text.slice(1) : text);
        return value => { const hit = re.test(S(value)); return not ? !hit : hit; };
    }
    // The values lists may set without a trusted list: uBlock Origin's set.
    function safeValue(raw) {
        switch (raw) {
            case 'undefined': return { v: undefined };
            case 'false': case 'no': return { v: false };
            case 'true': case 'yes': return { v: true };
            case 'null': return { v: null };
            case "''": case '': case 'emptyStr': return { v: '' };
            case 'noopFunc': return { v: function () {} };
            case 'trueFunc': return { v: function () { return true; } };
            case 'falseFunc': return { v: function () { return false; } };
            case 'throwFunc': return { v: function () { throw new TypeError(); } };
            case 'noopCallbackFunc': return { v: function () { return function () {}; } };
            case 'emptyArr': case '[]': return { v: [] };
            case 'emptyObj': case '{}': return { v: {} };
            case 'noopPromiseResolve': return { v: function () { return win.Promise.resolve(); } };
            case 'noopPromiseReject': return { v: function () { return win.Promise.reject(); } };
        }
        if (/^-?\d+(\.\d+)?$/.test(raw)) {
            const n = Number(raw);
            if (Math.abs(n) <= 32767) return { v: n };
        }
        return null;
    }
    function trustedValue(raw) {
        const safe = safeValue(raw);
        if (safe) return safe;
        try { return { v: jsonParse(raw) }; } catch (_) { return { v: raw }; }
    }
    // Pairs after the fixed arguments: ['propsToMatch', '/x/', 'stay', '1'] → {propsToMatch: '/x/', stay: '1'}.
    function extras(list) {
        const out = {};
        for (let i = 0; i + 1 < list.length; i += 2) out[list[i]] = list[i + 1];
        return out;
    }
    // propsToMatch: `url:/re/ method:POST`, or a bare pattern for the URL.
    function requestMatcher(spec) {
        if (spec == null || spec === '') return () => true;
        const wants = [];
        for (const part of S(spec).split(/\s+/)) {
            if (!part) continue;
            const m = /^([a-zA-Z]+):(.*)$/.exec(part);
            if (m && !/^https?$/.test(m[1])) wants.push([m[1], needle(m[2])]);
            else wants.push(['url', needle(part)]);
        }
        return props => wants.every(([k, test]) => test(props[k] == null ? '' : props[k]));
    }
    // Every own property of an object or array, for walking.
    function children(node) {
        if (A.isArray(node)) return node.map((v, i) => [i, v]);
        if (node && typeof node === 'object') return ownKeys(node).filter(k => typeof k === 'string').map(k => [k, node[k]]);
        return [];
    }

    // A chain like `a.b.c` on `root`: `onLeaf(owner, prop)` once the owner exists, now or when it is assigned.
    // Several chains can wait on one property (uBlock filters sets three of ytInitialPlayerResponse's): they share
    // one accessor there, each called with what is assigned.
    const waiting = new win.WeakMap();
    function waitOn(owner, prop, onValue) {
        let props = waiting.get(owner);
        if (!props) { props = new win.Map(); waiting.set(owner, props); }
        const hooks = props.get(prop);
        if (hooks) { hooks.push(onValue); return; }
        const desc = getOwnDescriptor(owner, prop);
        if (desc && desc.configurable === false) return;
        const list = [onValue];
        props.set(prop, list);
        let held = owner[prop];
        try {
            defineProperty(owner, prop, {
                configurable: true, enumerable: true,
                get() { return held; },
                set(v) {
                    held = v;
                    if (v && (typeof v === 'object' || typeof v === 'function')) for (const hook of list.slice()) hook(v);
                },
            });
        } catch (_) { props.delete(prop); }
    }
    function onChain(root, chain, onLeaf) {
        const parts = chain.split('.');
        function step(owner, i) {
            const prop = parts[i];
            if (i === parts.length - 1) return onLeaf(owner, prop);
            const current = owner[prop];
            if (current && (typeof current === 'object' || typeof current === 'function')) {
                step(current, i + 1);
            }
            // Also when the page replaces the object later (YouTube sets a new player response per video).
            waitOn(owner, prop, v => step(v, i + 1));
        }
        step(root, 0);
    }

    // A function on `root` at `chain` wrapped in a Proxy, so it still prints as the page's own.
    function wrap(root, chain, handler) {
        const parts = chain.split('.');
        const prop = parts.pop();
        let owner = root;
        for (const p of parts) { owner = owner && owner[p]; }
        if (!owner || typeof owner[prop] !== 'function') return false;
        try { owner[prop] = new P(owner[prop], handler); } catch (_) { return false; }
        return true;
    }

    const magic = 'cra' + Math.random().toString(36).slice(2);
    const abortError = () => new win.ReferenceError(magic);
    try {
        const previous = win.onerror;
        win.onerror = new P(function () {}, {
            apply(target, self, args) {
                if (typeof args[0] === 'string' && args[0].includes(magic)) return true;
                return typeof previous === 'function' ? apply(previous, self, args) : false;
            },
        });
    } catch (_) {}

    // ---- JSON paths ---------------------------------------------------------------------------------------------
    // Lists name what to take out of (or change in) a page's data three ways, all read here:
    //   uBlock Origin's prune paths: `playerResponse.adPlacements`, `a.[].b` (each element), `a.*.b`, and
    //   `entries.[-].content.promoted_metadata` (removes the elements of `entries` that have that path);
    //   JSONPath: `$.data..["entries","items"][?(@.*.content.promoted_metadata)]`;
    //   uBlock Origin's edit paths: `[?.attestationRequest]..client[?.clientName=="WEB"]+={"clientScreen":"CHANNEL"}`.
    // A filter `[?…]` keeps an array's elements that match, and an object only when it matches itself.

    function splitTopLevel(text, sep) {
        const out = [];
        let depth = 0, quote = '', cur = '';
        for (let i = 0; i < text.length; i++) {
            const c = text[i];
            if (quote) { cur += c; if (c === '\\') { cur += text[++i] || ''; } else if (c === quote) quote = ''; continue; }
            if (c === '"' || c === "'") { quote = c; cur += c; continue; }
            if (c === '[' || c === '(' || c === '{') depth++;
            if (c === ']' || c === ')' || c === '}') depth--;
            if (depth === 0 && text.startsWith(sep, i)) { out.push(cur); cur = ''; i += sep.length - 1; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    // Steps: {key: [names]} (a name may be '*'), {deep: [names]}, {each: true}, {index: n}, {filter: cond},
    // {removeIf: steps} (prune paths' `[-]`).
    function parsePath(text) {
        let s = text.trim();
        const steps = [];
        if (s.startsWith('$')) s = s.slice(1);
        let i = 0;
        const readName = () => {
            let name = '';
            while (i < s.length && !'.[]'.includes(s[i])) name += s[i++];
            return name;
        };
        const readBracket = () => {
            let depth = 0, quote = '', j = i;
            for (; j < s.length; j++) {
                const c = s[j];
                if (quote) { if (c === '\\') j++; else if (c === quote) quote = ''; continue; }
                if (c === '"' || c === "'") { quote = c; continue; }
                if (c === '[') depth++;
                if (c === ']') { depth--; if (depth === 0) break; }
            }
            const inner = s.slice(i + 1, j);
            i = j + 1;
            return inner;
        };
        const bracketStep = inner => {
            if (inner === '' || inner === '*') return { each: true };
            if (inner === '-') return { removeMark: true };
            if (/^-?\d+$/.test(inner)) return { index: Number(inner) };
            if (inner.startsWith('?')) {
                let cond = inner.slice(1);
                if (cond.startsWith('(') && cond.endsWith(')')) cond = cond.slice(1, -1);
                return { filter: parseCondition(cond) };
            }
            const names = splitTopLevel(inner, ',').map(n => n.trim().replace(/^(['"])(.*)\1$/, '$2'));
            return { key: names };
        };
        while (i < s.length) {
            if (s.startsWith('..', i)) {
                i += 2;
                if (s[i] === '[') {
                    const st = bracketStep(readBracket());
                    steps.push(st.key ? { deep: st.key } : { deep: ['*'] }, ...(st.key ? [] : [st]));
                } else {
                    steps.push({ deep: [readName()] });
                }
                continue;
            }
            if (s[i] === '.') { i++; continue; }
            if (s[i] === '[') { steps.push(bracketStep(readBracket())); continue; }
            const name = readName();
            if (name === '' ) { i++; continue; }
            steps.push(name === '*' ? { each: true } : { key: [name] });
        }
        // `[-]` (removeMark) makes the rest a test on the array's elements.
        const mark = steps.findIndex(st => st.removeMark);
        if (mark >= 0) return steps.slice(0, mark).concat([{ removeIf: steps.slice(mark + 1) }]);
        return steps;
    }

    // `@.a.b`, `.a`, `!.a`, `.a=="x"`, `.a*="x"`, `.a=/re/`, `@.a&&!@.b`.
    function parseCondition(text) {
        const ors = splitTopLevel(text, '||');
        if (ors.length > 1) { const parts = ors.map(parseCondition); return node => parts.some(p => p(node)); }
        const ands = splitTopLevel(text, '&&');
        if (ands.length > 1) { const parts = ands.map(parseCondition); return node => parts.every(p => p(node)); }
        let t = text.trim();
        let not = false;
        if (t.startsWith('!')) { not = true; t = t.slice(1).trim(); }
        if (t.startsWith('@')) t = t.slice(1);
        const op = /^(.*?)(==|!=|\*=|\^=|\$=|=)(.*)$/s.exec(t);
        const path = parsePath(op ? op[1] : t);
        let test;
        if (!op) {
            test = node => select(node, path).length > 0;
        } else {
            const raw = op[3].trim();
            let want;
            try { want = jsonParse(raw); } catch (_) { want = raw.replace(/^(['"])(.*)\1$/, '$2'); }
            const re = op[2] === '=' ? pattern(raw) : null;
            const cmp = v => {
                switch (op[2]) {
                    case '==': return v === want;
                    case '!=': return v !== want;
                    case '*=': return typeof v === 'string' && v.includes(want);
                    case '^=': return typeof v === 'string' && v.startsWith(want);
                    case '$=': return typeof v === 'string' && v.endsWith(want);
                    default: return re.test(S(v));
                }
            };
            test = node => select(node, path).some(m => cmp(m.value));
        }
        return not ? node => !test(node) : test;
    }

    // Matches of `steps` under `root`: [{parent, key, value}], the root itself as {parent: null}.
    function select(root, steps) {
        let nodes = [{ parent: null, key: null, value: root }];
        for (const st of steps) {
            const next = [];
            for (const n of nodes) {
                const v = n.value;
                if (st.key) {
                    if (!v || typeof v !== 'object') continue;
                    for (const name of st.key) {
                        if (name === '*') { for (const [k, c] of children(v)) next.push({ parent: v, key: k, value: c }); }
                        else if (name in v) next.push({ parent: v, key: name, value: v[name] });
                    }
                } else if (st.each) {
                    for (const [k, c] of children(v)) next.push({ parent: v, key: k, value: c });
                } else if (st.index != null) {
                    if (A.isArray(v)) {
                        const i = st.index < 0 ? v.length + st.index : st.index;
                        if (i >= 0 && i < v.length) next.push({ parent: v, key: i, value: v[i] });
                    }
                } else if (st.deep) {
                    const walk = (node, depth) => {
                        if (!node || typeof node !== 'object' || depth > 64) return;
                        for (const [k, c] of children(node)) {
                            if (st.deep.includes('*') || st.deep.includes(k)) next.push({ parent: node, key: k, value: c });
                            walk(c, depth + 1);
                        }
                    };
                    walk(v, 0);
                } else if (st.filter) {
                    if (A.isArray(v)) {
                        v.forEach((c, i) => { if (st.filter(c)) next.push({ parent: v, key: i, value: c }); });
                    } else if (v && typeof v === 'object' && st.filter(v)) {
                        next.push(n);
                    }
                } else if (st.removeIf) {
                    if (A.isArray(v)) {
                        v.forEach((c, i) => { if (select(c, st.removeIf).length) next.push({ parent: v, key: i, value: c }); });
                    }
                }
            }
            nodes = next;
            if (!nodes.length) break;
        }
        return nodes;
    }

    // Removes the matches (array elements from the end, so indexes hold); true when anything went.
    function removeMatches(matches) {
        const byArray = new Map();
        let removed = false;
        for (const m of matches) {
            if (!m.parent) continue;
            if (A.isArray(m.parent)) {
                if (!byArray.has(m.parent)) byArray.set(m.parent, []);
                byArray.get(m.parent).push(m.key);
            } else { try { delete m.parent[m.key]; removed = true; } catch (_) {} }
        }
        for (const [arr, idx] of byArray) {
            for (const i of [...new Set(idx)].sort((a, b) => b - a)) { arr.splice(i, 1); removed = true; }
        }
        return removed;
    }

    // json-prune's arguments on a parsed object: prune paths (space-separated) when every needle path is there.
    function prune(obj, prunePaths, needlePaths) {
        if (!obj || typeof obj !== 'object') return false;
        const paths = S(prunePaths || '').split(/\s+/).filter(Boolean);
        if (!paths.length) return false;
        const needles = S(needlePaths || '').split(/\s+/).filter(Boolean);
        for (const n of needles) if (!select(obj, parsePath(n)).length) return false;
        let removed = false;
        for (const p of paths) removed = removeMatches(select(obj, parsePath(p))) || removed;
        return removed;
    }

    // An edit query: a path, then `+={…}` (merge), `=value` (set), `=repl({regex, replacement})`, or nothing
    // (remove). `trusted` allows the changes; otherwise only removal.
    function edit(obj, query, trusted) {
        if (!obj || typeof obj !== 'object') return false;
        let path = query, op = '', raw = '';
        const ops = splitTopLevel(query, '+=');
        if (ops.length > 1) { path = ops[0]; op = '+='; raw = ops.slice(1).join('+='); }
        else {
            const eq = splitTopLevel(query, '=');
            // A filter's own `=`/`==` is inside brackets, so a top-level `=` is the assignment.
            if (eq.length > 1) { path = eq[0]; op = '='; raw = eq.slice(1).join('='); }
        }
        const matches = select(obj, parsePath(path));
        if (!matches.length) return false;
        if (!op) return removeMatches(matches);
        if (!trusted) return false;
        let value;
        const repl = /^repl\((.*)\)$/s.exec(raw.trim());
        if (repl) {
            let spec;
            try { spec = jsonParse(repl[1]); } catch (_) { return false; }
            const re = pattern('/' + spec.regex.replace(/^\/|\/$/g, '') + '/' + (spec.flags || ''));
            for (const m of matches) if (m.parent && typeof m.value === 'string') m.parent[m.key] = m.value.replace(re, spec.replacement || '');
            return true;
        }
        try { value = jsonParse(raw); } catch (_) { value = trustedValue(raw.trim()).v; }
        for (const m of matches) {
            if (op === '+=') {
                if (m.value && typeof m.value === 'object' && value && typeof value === 'object') O.assign(m.value, value);
            } else if (m.parent) m.parent[m.key] = value;
        }
        return true;
    }

    // ---- Network responses ---------------------------------------------------------------------------------------

    const fetchEdits = [];   // {match(props), text(body) → body|null}
    const xhrEdits = [];
    const fetchBlocks = [];  // {match(props), body}
    const xhrBlocks = [];

    function fetchProps(args) {
        const [input, init] = args;
        const props = { url: '', method: 'GET' };
        if (typeof input === 'string' || (input && typeof input.href === 'string')) props.url = S(input.href || input);
        else if (input && typeof input.url === 'string') { props.url = input.url; props.method = input.method || 'GET'; }
        if (init && init.method) props.method = S(init.method).toUpperCase();
        try { props.url = new win.URL(props.url, loc.href).href; } catch (_) {}
        return props;
    }

    let fetchWrapped = false;
    function wrapFetch() {
        if (fetchWrapped || typeof win.fetch !== 'function') return;
        fetchWrapped = true;
        const Response = win.Response;
        wrap(win, 'fetch', {
            apply(target, self, args) {
                const props = fetchProps(args);
                const block = fetchBlocks.find(b => b.match(props));
                if (block) {
                    return win.Promise.resolve(new Response(block.body, { status: 200, statusText: 'OK' }));
                }
                const edits = fetchEdits.filter(e => e.match(props));
                const pending = apply(target, self, args);
                if (!edits.length) return pending;
                return pending.then(response => response.clone().text().then(text => {
                    let body = text;
                    for (const e of edits) { const next = e.text(body); if (next != null) body = next; }
                    if (body === text) return response;
                    const edited = new Response(body, { status: response.status, statusText: response.statusText, headers: response.headers });
                    try {
                        defineProperty(edited, 'url', { value: response.url });
                        defineProperty(edited, 'type', { value: response.type });
                        defineProperty(edited, 'redirected', { value: response.redirected });
                    } catch (_) {}
                    return edited;
                }).catch(() => response));
            },
        });
    }

    let xhrWrapped = false;
    function wrapXHR() {
        const XHR = win.XMLHttpRequest;
        if (xhrWrapped || typeof XHR !== 'function') return;
        xhrWrapped = true;
        const proto = XHR.prototype;
        const state = new win.WeakMap();
        wrap(proto, 'open', {
            apply(target, self, args) {
                let url = S(args[1] == null ? '' : args[1]);
                try { url = new win.URL(url, loc.href).href; } catch (_) {}
                state.set(self, { props: { method: S(args[0] || 'GET').toUpperCase(), url } });
                return apply(target, self, args);
            },
        });
        wrap(proto, 'send', {
            apply(target, self, args) {
                const s = state.get(self);
                if (s) {
                    s.block = xhrBlocks.find(b => b.match(s.props));
                    s.edits = xhrEdits.filter(e => e.match(s.props));
                }
                if (s && s.block) {
                    // A request a list stops: it ends at once, empty, as a successful one.
                    for (const [k, v] of [['readyState', 4], ['status', 200], ['statusText', 'OK'], ['responseText', s.block.body], ['response', s.block.body]]) {
                        try { defineProperty(self, k, { value: v, configurable: true }); } catch (_) {}
                    }
                    win.setTimeout(() => {
                        for (const type of ['readystatechange', 'load', 'loadend']) {
                            try { self.dispatchEvent(new win.Event(type)); } catch (_) {}
                        }
                    }, 1);
                    return undefined;
                }
                return apply(target, self, args);
            },
        });
        const editedText = self => {
            const s = state.get(self);
            if (!s || !s.edits || !s.edits.length || self.readyState !== 4) return null;
            if (s.done !== undefined) return s.done;
            const type = self.responseType;
            if (type !== '' && type !== 'text' && type !== 'json') return (s.done = null);
            let text;
            try { text = type === 'json' ? jsonStringify(getResponse.call(self)) : getText.call(self); } catch (_) { return (s.done = null); }
            let body = text;
            for (const e of s.edits) { const next = e.text(body); if (next != null) body = next; }
            s.done = body === text ? null : body;
            return s.done;
        };
        const textDesc = getOwnDescriptor(proto, 'responseText');
        const responseDesc = getOwnDescriptor(proto, 'response');
        const getText = textDesc && textDesc.get;
        const getResponse = responseDesc && responseDesc.get;
        if (getText) {
            defineProperty(proto, 'responseText', { ...textDesc, get: new P(getText, {
                apply(target, self, args) { const e = editedText(self); return e != null ? e : apply(target, self, args); },
            }) });
        }
        if (getResponse) {
            defineProperty(proto, 'response', { ...responseDesc, get: new P(getResponse, {
                apply(target, self, args) {
                    const e = editedText(self);
                    if (e == null) return apply(target, self, args);
                    if (self.responseType === 'json') { try { return jsonParse(e); } catch (_) { return null; } }
                    return e;
                },
            }) });
        }
    }

    const jsonText = fn => text => {
        let obj;
        try { obj = jsonParse(text); } catch (_) { return null; }
        return fn(obj) ? jsonStringify(obj) : null;
    };
    const replaceText = (pat, replacement) => {
        const re = pattern(pat);
        return text => { const next = S(text).replace(re, replacement || ''); return next === text ? null : next; };
    };

    // JSON.parse and Response.json, for json-prune and json-edit.
    const parseEdits = [];
    let parseWrapped = false;
    function wrapParse() {
        if (parseWrapped) return;
        parseWrapped = true;
        const run = obj => { for (const e of parseEdits) { try { e(obj); } catch (_) {} } return obj; };
        wrap(win, 'JSON.parse', { apply(target, self, args) { return run(apply(target, self, args)); } });
        if (win.Response && win.Response.prototype && win.Response.prototype.json) {
            wrap(win.Response.prototype, 'json', {
                apply(target, self, args) { return apply(target, self, args).then(run); },
            });
        }
    }

    // ---- DOM ----------------------------------------------------------------------------------------------------

    function whenDOM(fn, behavior) {
        const doc = win.document;
        if (!doc) return;
        const run = () => { try { fn(); } catch (_) {} };
        const b = S(behavior || '');
        if (b.includes('asap')) run();
        if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', run, { once: true });
        else run();
        if (b.includes('complete')) win.addEventListener('load', run, { once: true });
        if (b.includes('stay')) {
            let timer = 0;
            const observer = new win.MutationObserver(() => {
                if (timer) return;
                timer = win.setTimeout(() => { timer = 0; run(); }, 50);
            });
            const start = () => observer.observe(doc.documentElement || doc, { childList: true, subtree: true, attributes: true });
            if (doc.documentElement) start(); else doc.addEventListener('DOMContentLoaded', start, { once: true });
        }
    }

    // Text of nodes as the parser inserts them (scripts before they run: the parser lets observers see a script
    // before running it).
    const nodeTextEdits = [];
    let nodeWatch = null;
    function watchNodes() {
        if (nodeWatch || !win.MutationObserver || !win.document) return;
        const handle = node => {
            const name = S(node.nodeName).toLowerCase();
            for (const e of nodeTextEdits) {
                if (e.name !== name && e.name !== '*') continue;
                const text = node.textContent;
                if (!e.condition.test(text)) continue;
                const next = e.edit(text);
                if (next != null && next !== text) node.textContent = next;
            }
        };
        nodeWatch = new win.MutationObserver(records => {
            for (const r of records) for (const n of r.addedNodes) {
                handle(n);
                if (n.nodeType === 3 && n.parentNode) handle(n.parentNode);
            }
        });
        nodeWatch.observe(win.document, { childList: true, subtree: true });
    }

    // ---- The scriptlets -----------------------------------------------------------------------------------------

    function setConstant(chain, raw, trusted) {
        const parsed = trusted ? trustedValue(raw) : safeValue(raw);
        if (!parsed || !chain) return;
        const value = parsed.v;
        onChain(win, chain, (owner, prop) => {
            const desc = getOwnDescriptor(owner, prop);
            if (desc && desc.configurable === false) return;
            try {
                defineProperty(owner, prop, { configurable: true, enumerable: true, get() { return value; }, set() {} });
            } catch (_) {}
        });
    }

    const impl = {
        'set-constant': (chain, value) => setConstant(chain, value, false),
        'trusted-set-constant': (chain, value) => setConstant(chain, value, true),
        'abort-on-property-read': chain => onChain(win, chain, (owner, prop) => {
            try { defineProperty(owner, prop, { configurable: true, get() { throw abortError(); }, set() {} }); } catch (_) {}
        }),
        'abort-on-property-write': chain => onChain(win, chain, (owner, prop) => {
            try { defineProperty(owner, prop, { configurable: true, get() { return undefined; }, set() { throw abortError(); } }); } catch (_) {}
        }),
        'abort-current-script': (chain, needleText, context) => {
            const matches = needle(needleText || '');
            const inScript = () => {
                const script = win.document && win.document.currentScript;
                if (!script) return false;
                const text = script.src ? S(script.src) : S(script.textContent);
                return matches(text) && (!context || needle(context)(text));
            };
            onChain(win, chain, (owner, prop) => {
                const desc = getOwnDescriptor(owner, prop) || { value: owner[prop], writable: true };
                if (desc.configurable === false) return;
                let held = desc.get ? undefined : desc.value;
                try {
                    defineProperty(owner, prop, {
                        configurable: true,
                        get() { if (inScript()) throw abortError(); return desc.get ? apply(desc.get, this, []) : held; },
                        set(v) { if (inScript()) throw abortError(); if (desc.set) apply(desc.set, this, [v]); else held = v; },
                    });
                } catch (_) {}
            });
        },
        'json-prune': (prunePaths, needlePaths) => {
            wrapParse();
            parseEdits.push(obj => prune(obj, prunePaths, needlePaths));
        },
        'json-edit': query => { wrapParse(); parseEdits.push(obj => edit(obj, query, false)); },
        'trusted-json-edit': query => { wrapParse(); parseEdits.push(obj => edit(obj, query, true)); },
        'json-prune-fetch-response': (prunePaths, needlePaths, ...rest) => {
            const match = requestMatcher(extras(rest).propsToMatch);
            wrapFetch();
            fetchEdits.push({ match, text: jsonText(obj => prune(obj, prunePaths, needlePaths)) });
        },
        'json-prune-xhr-response': (prunePaths, needlePaths, ...rest) => {
            const match = requestMatcher(extras(rest).propsToMatch);
            wrapXHR();
            xhrEdits.push({ match, text: jsonText(obj => prune(obj, prunePaths, needlePaths)) });
        },
        'json-edit-fetch-response': (query, ...rest) => {
            wrapFetch();
            fetchEdits.push({ match: requestMatcher(extras(rest).propsToMatch), text: jsonText(obj => edit(obj, query, false)) });
        },
        'trusted-json-edit-fetch-response': (query, ...rest) => {
            wrapFetch();
            fetchEdits.push({ match: requestMatcher(extras(rest).propsToMatch), text: jsonText(obj => edit(obj, query, true)) });
        },
        'json-edit-xhr-response': (query, ...rest) => {
            wrapXHR();
            xhrEdits.push({ match: requestMatcher(extras(rest).propsToMatch), text: jsonText(obj => edit(obj, query, false)) });
        },
        'trusted-json-edit-xhr-response': (query, ...rest) => {
            wrapXHR();
            xhrEdits.push({ match: requestMatcher(extras(rest).propsToMatch), text: jsonText(obj => edit(obj, query, true)) });
        },
        'trusted-replace-fetch-response': (pat, replacement, props) => {
            wrapFetch();
            fetchEdits.push({ match: requestMatcher(props), text: replaceText(pat, replacement) });
        },
        'trusted-replace-xhr-response': (pat, replacement, props) => {
            wrapXHR();
            xhrEdits.push({ match: requestMatcher(props), text: replaceText(pat, replacement) });
        },
        'edit-inbound-object': (chain, argPos, query) => inbound(chain, argPos, query, false),
        'trusted-edit-inbound-object': (chain, argPos, query) => inbound(chain, argPos, query, true),
        'edit-outbound-object': (chain, query) => outbound(chain, query, false),
        'trusted-edit-outbound-object': (chain, query) => outbound(chain, query, true),
        'no-setTimeout-if': (needleText, delay) => defuseTimer('setTimeout', needleText, delay),
        'no-setInterval-if': (needleText, delay) => defuseTimer('setInterval', needleText, delay),
        'adjust-setTimeout': (needleText, delay, boost) => boostTimer('setTimeout', needleText, delay, boost),
        'adjust-setInterval': (needleText, delay, boost) => boostTimer('setInterval', needleText, delay, boost),
        'addEventListener-defuser': (type, needleText) => {
            const types = needle(type || '');
            const handlers = needle(needleText || '');
            const proto = win.EventTarget && win.EventTarget.prototype;
            if (!proto) return;
            wrap(proto, 'addEventListener', {
                apply(target, self, args) {
                    let text = '';
                    try { text = S(args[1]); } catch (_) {}
                    if (types(S(args[0])) && handlers(text)) return undefined;
                    return apply(target, self, args);
                },
            });
        },
        'no-window-open-if': (needleText, delay, decoy) => {
            const matches = needle(needleText || '');
            wrap(win, 'open', {
                apply(target, self, args) {
                    if (matches(S(args[0] == null ? '' : args[0]))) return null;
                    return apply(target, self, args);
                },
            });
        },
        'noeval-if': needleText => {
            const matches = needle(needleText || '');
            wrap(win, 'eval', { apply(target, self, args) { if (matches(S(args[0]))) return undefined; return apply(target, self, args); } });
        },
        'no-fetch-if': (props, body) => {
            wrapFetch();
            const match = requestMatcher(props);
            fetchBlocks.push({ match, body: body === 'emptyObj' ? '{}' : body === 'emptyArr' ? '[]' : '' });
        },
        'no-xhr-if': (props, body) => {
            wrapXHR();
            xhrBlocks.push({ match: requestMatcher(props), body: body === 'emptyObj' ? '{}' : body === 'emptyArr' ? '[]' : '' });
        },
        'remove-attr': (attrs, selector, behavior) => {
            const names = S(attrs || '').split('|').filter(Boolean);
            if (!names.length) return;
            const sel = selector || names.map(n => '[' + n + ']').join(',');
            whenDOM(() => {
                for (const el of win.document.querySelectorAll(sel)) for (const n of names) el.removeAttribute(n);
            }, behavior);
        },
        'remove-class': (classes, selector, behavior) => {
            const names = S(classes || '').split('|').filter(Boolean);
            if (!names.length) return;
            const sel = selector || names.map(n => '.' + n).join(',');
            whenDOM(() => {
                for (const el of win.document.querySelectorAll(sel)) for (const n of names) el.classList.remove(n);
            }, behavior);
        },
        'set-attr': (selector, attr, value) => {
            if (!selector || !attr || /^on/i.test(attr)) return;
            const v = value == null ? '' : S(value);
            if (!(v === '' || v === 'true' || v === 'false' || /^\d+$/.test(v) && Number(v) <= 32767 || /^\[[\w-]+\]$/.test(v))) return;
            whenDOM(() => {
                for (const el of win.document.querySelectorAll(selector)) {
                    el.setAttribute(attr, /^\[.+\]$/.test(v) ? (el.getAttribute(v.slice(1, -1)) || '') : v);
                }
            }, 'stay');
        },
        'replace-node-text': (name, pat, replacement, ...rest) => nodeText(name, pat, replacement, rest, true),
        'trusted-replace-node-text': (name, pat, replacement, ...rest) => nodeText(name, pat, replacement, rest, true),
        'remove-node-text': (name, pat, ...rest) => nodeText(name, pat, '', rest, true),
        'set-cookie': (name, value, path) => {
            const v = safeValue(value);
            if (!name || !v || typeof v.v === 'function' || typeof v.v === 'object' && v.v !== null) return;
            try { win.document.cookie = encodeURIComponent(name) + '=' + encodeURIComponent(S(v.v)) + '; path=' + (path === 'none' ? '' : (path || '/')); } catch (_) {}
        },
        'set-local-storage-item': (key, value) => storage('localStorage', key, value),
        'set-session-storage-item': (key, value) => storage('sessionStorage', key, value),
        'nowebrtc': () => {
            const fake = function () { throw new win.DOMException('', 'NotAllowedError'); };
            for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection']) {
                if (win[name]) try { win[name] = new P(win[name], { construct: fake }); } catch (_) {}
            }
        },
    };

    function inbound(chain, argPos, query, trusted) {
        const pos = Number(argPos) || 0;
        wrap(win, chain, {
            apply(target, self, args) {
                const arg = args[pos];
                if (arg && typeof arg === 'object') {
                    let copy;
                    try { copy = jsonParse(jsonStringify(arg)); } catch (_) { copy = null; }
                    if (copy && edit(copy, query, trusted)) { args = A.from(args); args[pos] = copy; }
                }
                return apply(target, self, args);
            },
        });
    }
    function outbound(chain, query, trusted) {
        wrap(win, chain, {
            apply(target, self, args) {
                const result = apply(target, self, args);
                if (result && typeof result === 'object') { try { edit(result, query, trusted); } catch (_) {} }
                return result;
            },
        });
    }
    function defuseTimer(name, needleText, delay) {
        const matches = needle(needleText || '');
        const wantDelay = delay == null || delay === '' ? null : delay;
        wrap(win, name, {
            apply(target, self, args) {
                let text = '';
                try { text = S(args[0]); } catch (_) {}
                const d = Number(args[1]) || 0;
                let delayHit = true;
                if (wantDelay !== null) {
                    const not = S(wantDelay).startsWith('!');
                    const n = Number(not ? S(wantDelay).slice(1) : wantDelay);
                    delayHit = not ? d !== n : d === n;
                }
                if (matches(text) && delayHit) return apply(target, self, [function () {}, d]);
                return apply(target, self, args);
            },
        });
    }
    function boostTimer(name, needleText, delay, boost) {
        const matches = needle(needleText || '');
        const want = delay === '*' ? null : Number(delay || 1000);
        let factor = Number(boost);
        if (!(factor >= 0.001 && factor <= 50)) factor = 0.05;
        wrap(win, name, {
            apply(target, self, args) {
                let text = '';
                try { text = S(args[0]); } catch (_) {}
                const d = Number(args[1]) || 0;
                if (matches(text) && (want === null || d === want)) { args = A.from(args); args[1] = d * factor; }
                return apply(target, self, args);
            },
        });
    }
    function nodeText(name, pat, replacement, rest, trusted) {
        const extra = extras(rest);
        if (!trusted && replacement) return;
        const re = pattern(pat, null);
        const global = re.global;
        let count = 0;
        const limit = Number(extra.sedCount) || 0;
        nodeTextEdits.push({
            name: S(name || '').toLowerCase(),
            condition: extra.condition ? pattern(extra.condition) : /^/,
            edit: text => {
                if (limit && count >= limit) return null;
                if (!re.test(text)) return null;
                re.lastIndex = 0;
                count += 1;
                return global ? text.replace(re, replacement) : text.replace(re, replacement);
            },
        });
        watchNodes();
    }
    function storage(which, key, value) {
        if (!key) return;
        let store;
        try { store = win[which]; } catch (_) { return; }
        if (!store) return;
        try {
            if (value === '$remove$') { store.removeItem(key); return; }
            const v = safeValue(value);
            if (!v || typeof v.v === 'function') return;
            store.setItem(key, typeof v.v === 'object' ? jsonStringify(v.v) : S(v.v));
        } catch (_) {}
    }

    for (const call of calls) {
        const fn = impl[call[0]];
        if (!fn) continue;
        try { fn(...call.slice(1)); } catch (_) {}
    }
})
