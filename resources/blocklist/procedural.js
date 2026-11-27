// Cra's procedural element hiding (#845). Copyright Cra contributors, MIT License (written for Cra; the operator
// names are the filter lists' syntax).
//
// Runs in Cra's isolated world on a page. Cra calls it with the selectors of the lists in use for the page's host
// (CraCore ProceduralTable): uBlock Origin's procedural operators (:has-text, :upward, :xpath, :matches-css,
// :min-text-length, :matches-attr, :matches-path, :remove, :remove-attr, :remove-class, :style), AdGuard's and
// Adblock Plus's names for them (:contains, :-abp-contains, :-abp-has, :if, :if-not, :nth-ancestor), and selectors
// too complex for Cra's stylesheet. What they select is hidden (or removed, or restyled), again as the page changes.
// A second call on the same document replaces the selectors.
(function craProcedural(selectors, scope) {
    'use strict';
    const win = scope;
    const doc = win.document;
    if (!doc) return 0;
    const state = win.__craProcedural || (win.__craProcedural = { tasks: [], hidden: new Set(), timer: 0, observer: null });

    const proceduralOps = new Set(['has-text', 'contains', '-abp-contains', 'has', '-abp-has', 'if', 'if-not', 'not',
        'upward', 'nth-ancestor', 'xpath', 'matches-css', 'matches-css-before', 'matches-css-after', 'min-text-length',
        'matches-attr', 'matches-path', 'remove', 'remove-attr', 'remove-class', 'watch-attr', 'style']);
    const actions = new Set(['remove', 'remove-attr', 'remove-class', 'style']);

    function textPattern(arg) {
        const t = String(arg).trim().replace(/^(['"])(.*)\1$/s, '$2');
        const m = /^\/(.+)\/([gimsu]*)$/s.exec(t);
        if (m) { try { return new RegExp(m[1], m[2].replace('g', '')); } catch (_) { return /(?!)/; } }
        return { test: s => String(s).includes(t) };
    }

    // `div.a:has-text(Ad):upward(2) > span` → {base: 'div.a', ops: [['has-text','Ad'],['upward','2'],['css','> span']]}.
    function compile(text) {
        let s = text.trim();
        if (s.startsWith('#?#')) s = s.slice(3);
        const ops = [];
        let base = '';
        let i = 0, plain = '';
        const flushPlain = () => {
            if (!plain.trim()) { plain = ''; return; }
            if (!ops.length && base === '') base = plain.trim(); else ops.push(['css', plain.trim()]);
            plain = '';
        };
        while (i < s.length) {
            const c = s[i];
            if (c === '"' || c === "'") {
                const end = s.indexOf(c, i + 1);
                plain += s.slice(i, end < 0 ? s.length : end + 1);
                i = end < 0 ? s.length : end + 1;
                continue;
            }
            if (c === '[') {
                let depth = 0, j = i;
                for (; j < s.length; j++) { if (s[j] === '[') depth++; else if (s[j] === ']' && --depth === 0) break; }
                plain += s.slice(i, j + 1);
                i = j + 1;
                continue;
            }
            if (c === ':') {
                const m = /^:(-?[a-z][a-z-]*)\(/.exec(s.slice(i));
                if (m && proceduralOps.has(m[1]) && !(m[1] === 'has' || m[1] === 'not') || m && (m[1] === 'has' || m[1] === 'not') && needsProcedural(argAt(s, i + m[0].length - 1))) {
                    const open = i + m[0].length - 1;
                    const arg = argAt(s, open);
                    flushPlain();
                    if (!ops.length && base === '') base = '*';
                    ops.push([m[1], arg]);
                    i = open + arg.length + 2;
                    continue;
                }
            }
            plain += c;
            i++;
        }
        flushPlain();
        return { base: base || '*', ops };
    }
    // The text between the parenthesis at `open` and its match.
    function argAt(s, open) {
        let depth = 0, quote = '';
        for (let j = open; j < s.length; j++) {
            const c = s[j];
            if (quote) { if (c === '\\') j++; else if (c === quote) quote = ''; continue; }
            if (c === '"' || c === "'") { quote = c; continue; }
            if (c === '(') depth++;
            else if (c === ')' && --depth === 0) return s.slice(open + 1, j);
        }
        return s.slice(open + 1);
    }
    function needsProcedural(arg) {
        for (const op of proceduralOps) if (arg.includes(':' + op + '(') && op !== 'has' && op !== 'not') return true;
        try { doc.createDocumentFragment().querySelector(arg.startsWith('>') ? ':scope ' + arg : arg); return false; } catch (_) { return true; }
    }

    function query(root, css) {
        try {
            if (root === doc) return Array.from(doc.querySelectorAll(css));
            const rel = /^[>+~]/.test(css) ? ':scope ' + css : css;
            if (/^[+~]/.test(css)) return Array.from(root.parentElement ? root.parentElement.querySelectorAll(':scope > *') : []).filter(e => e.matches(css.replace(/^[+~]\s*/, '')) && root.compareDocumentPosition(e) & 4);
            return Array.from(root.querySelectorAll(rel));
        } catch (_) { return []; }
    }

    // The elements a compiled selector selects, and the action its last operator asks for.
    function run(c, root) {
        let nodes = query(root || doc, c.base);
        let action = null;
        for (const [op, arg] of c.ops) {
            if (!nodes.length) break;
            switch (op) {
                case 'css': nodes = unique(nodes.flatMap(n => query(n, arg))); break;
                case 'has-text': case 'contains': case '-abp-contains': {
                    const p = textPattern(arg);
                    nodes = nodes.filter(n => p.test(n.textContent || ''));
                    break;
                }
                case 'has': case '-abp-has': case 'if': {
                    const inner = compile(arg);
                    nodes = nodes.filter(n => within(n, inner));
                    break;
                }
                case 'not': case 'if-not': {
                    const inner = compile(arg);
                    const out = new Set(run(inner).nodes);
                    nodes = nodes.filter(n => !out.has(n));
                    break;
                }
                case 'upward': case 'nth-ancestor': {
                    const n = Number(arg);
                    nodes = unique(nodes.map(node => {
                        if (n > 0 && n < 256) { let p = node; for (let k = 0; k < n && p; k++) p = p.parentElement; return p; }
                        try { return node.parentElement && node.parentElement.closest(arg); } catch (_) { return null; }
                    }).filter(Boolean));
                    break;
                }
                case 'xpath': {
                    const out = [];
                    for (const n of nodes) {
                        try {
                            const r = doc.evaluate(arg, n === doc.documentElement && c.base === '*' ? doc : n, null, 7, null);
                            for (let k = 0; k < r.snapshotLength; k++) { const e = r.snapshotItem(k); if (e && e.nodeType === 1) out.push(e); }
                        } catch (_) {}
                        if (c.base === '*') break;
                    }
                    nodes = unique(out);
                    break;
                }
                case 'matches-css': case 'matches-css-before': case 'matches-css-after': {
                    const colon = arg.indexOf(':');
                    if (colon < 0) { nodes = []; break; }
                    const prop = arg.slice(0, colon).trim();
                    const p = textPattern(arg.slice(colon + 1).trim());
                    const pseudo = op === 'matches-css-before' ? '::before' : op === 'matches-css-after' ? '::after' : null;
                    nodes = nodes.filter(n => { try { return p.test(win.getComputedStyle(n, pseudo).getPropertyValue(prop)); } catch (_) { return false; } });
                    break;
                }
                case 'min-text-length': { const n = Number(arg) || 0; nodes = nodes.filter(e => (e.textContent || '').length >= n); break; }
                case 'matches-attr': {
                    const m = /^\s*("[^"]*"|'[^']*'|\/[^=]*\/|[^=]+)\s*(?:=\s*(.*))?$/s.exec(arg);
                    if (!m) { nodes = []; break; }
                    const name = textPattern(m[1]);
                    const value = m[2] != null ? textPattern(m[2]) : null;
                    nodes = nodes.filter(e => Array.from(e.attributes).some(a => (name.test(a.name)) && (!value || value.test(a.value))));
                    break;
                }
                case 'matches-path': {
                    const p = textPattern(arg);
                    if (!p.test(win.location.pathname + win.location.search)) nodes = [];
                    break;
                }
                case 'watch-attr': break;
                default:
                    if (actions.has(op)) action = [op, arg];
            }
        }
        return { nodes, action };
    }
    // Whether `inner` selects anything under `node` (`> x` its children, `x` its descendants).
    function within(node, inner) {
        return run(inner, node).nodes.some(e => e !== node && node.contains(e));
    }
    function unique(list) { return Array.from(new Set(list)); }

    const attr = state.attr || (state.attr = 'cra-h' + Math.random().toString(36).slice(2, 10));
    if (!state.sheet) {
        try {
            state.sheet = new win.CSSStyleSheet();
            state.sheet.replaceSync('[' + attr + ']{display:none!important}');
            doc.adoptedStyleSheets = [...doc.adoptedStyleSheets, state.sheet];
        } catch (_) { state.sheet = null; }
    }

    function hide(el) {
        if (state.sheet) el.setAttribute(attr, '');
        else el.style.setProperty('display', 'none', 'important');
        state.hidden.add(el);
    }

    function pass() {
        const keep = new Set();
        let n = 0;
        for (const task of state.tasks) {
            let result;
            try { result = run(task); } catch (_) { continue; }
            for (const el of result.nodes) {
                if (!el || el.nodeType !== 1 || el === doc.documentElement || el === doc.body) continue;
                const a = result.action;
                if (!a) { hide(el); keep.add(el); n++; }
                else if (a[0] === 'remove') { el.remove(); n++; }
                else if (a[0] === 'remove-attr') { for (const name of a[1].split('|')) el.removeAttribute(name.trim()); n++; }
                else if (a[0] === 'remove-class') { for (const name of a[1].split('|')) el.classList.remove(name.trim()); n++; }
                else if (a[0] === 'style') { el.style.cssText += ';' + a[1].replace(/;?\s*$/, '').split(';').map(d => d.includes('!important') ? d : d + ' !important').join(';'); n++; }
            }
        }
        // What a changed rule no longer selects comes back.
        for (const el of state.hidden) if (!keep.has(el)) { el.removeAttribute(attr); state.hidden.delete(el); }
        state.count = n;
        return n;
    }

    state.tasks = (selectors || []).map(s => { try { return compile(s); } catch (_) { return null; } }).filter(Boolean);
    if (!state.observer && win.MutationObserver) {
        state.observer = new win.MutationObserver(() => {
            if (state.timer) return;
            const started = Date.now();
            state.timer = win.setTimeout(() => {
                state.timer = 0;
                const t0 = Date.now();
                pass();
                // A page that changes all the time doesn't get a pass on every change.
                state.delay = Date.now() - t0 > 30 ? 500 : 100;
            }, state.delay || 100);
            void started;
        });
        state.observer.observe(doc, { childList: true, subtree: true, characterData: true });
    }
    return pass();
})
