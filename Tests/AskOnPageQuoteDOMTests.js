// Executes the production generated script against a small, controlled DOM surface. No browser engine proof.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const script = fs.readFileSync(process.argv[2], 'utf8').trim(), cut = script.lastIndexOf('})(');
const parameters = JSON.parse(script.slice(cut + 3, -1));
let checks = 0;
function expect(value, message) { assert.ok(value, message); checks++; }
function fixture(children) {
  const effects = {selection: null, scrolls: 0, largestRead: 0};
  const document = {URL: parameters.url, contentType: 'text/html'};
  function element(tag, children = [], attributes = {}, display = 'inline') {
    return {nodeType: 1, tagName: tag, children, display, attributes,
      hasAttribute(key) { return key in this.attributes; }, getAttribute(key) { return this.attributes[key] ?? null; },
      scrollIntoView() { effects.scrolls++; }};
  }
  function text(data) { return {nodeType: 3, data, get length() { return this.data.length; }, substringData(a, b) {
    effects.largestRead = Math.max(effects.largestRead, b); return this.data.slice(a, a + b); }}; }
  function connect(node, parent = null) {
    node.parentElement = parent; node.ownerDocument = document; node.isConnected = true;
    if (node.children) {
      node.firstChild = node.children[0] ?? null;
      node.children.forEach((child, i) => { child.nextSibling = node.children[i+1] ?? null; connect(child, node); });
    }
    return node;
  }
  document.body = connect(element('BODY', children({element, text}), {}, 'block'));
  document.createRange = () => ({collapsed: false, setStart(node, offset) { this.start = [node, offset]; },
    setEnd(node, offset) { this.end = [node, offset]; }, getClientRects() { return [{}]; }});
  const context = vm.createContext({document, Intl, Set, Map, getComputedStyle: node => ({display: node.display, visibility: 'visible'}),
    getSelection: () => ({removeAllRanges() { effects.selection = null; }, addRange(range) { effects.selection = range; }})});
  return {document, effects, context, element, text, connect};
}
function run(f, quote, match = null, lease = parameters.lease) {
  return vm.runInContext(script.slice(0, cut + 3) + JSON.stringify({...parameters, quote, match, lease}) + ')', f.context);
}
function find(f, quote) { const lookup = run(f, quote); expect(lookup.found, 'exact quote has a bounded lookup');
  expect(f.effects.scrolls === 0 && f.effects.selection === null, 'lookup never mutates selection or scroll');
  const result = run(f, quote, lookup); expect(result.found && f.effects.scrolls === 1, 'fresh validated range effects complete'); return lookup; }
// promise: #393
function literalInlineUnicode() {
  const f = fixture(({element: e, text: t}) => [e('P', [t('The cafe'), e('EM', [t('\u0301 opens\t at ')]), t('09:30. 👩‍🔬 & <literal> “yes”.')])]);
  find(f, 'The café opens at 09:30. 👩‍🔬 & <literal> “yes”.');
  expect(f.effects.selection.start[0].data === 'The cafe' && f.effects.selection.end[1] === f.document.body.firstChild.children[2].length,
    'canonical Unicode split across inline nodes maps to the exact original endpoints');
  for (const quote of ['the café opens at 09:30.', 'The cafe opens at 09:30.', '09:30!', '👩', '&amp;', 'missing']) {
    expect(!run(f, quote).found, 'case, accents, punctuation, graphemes, transport spelling and absent text never get repaired');
  }
}
// promise: #393
function liveRevalidationAndLease() {
  const f = fixture(({text: t}) => [t('First repeat. Second repeat.')]);
  const match = find(f, 'repeat.');
  expect(match.startOffset === 6, 'repeated quotes deterministically select the first exact occurrence');
  const before = f.effects.scrolls;
  f.document.body.firstChild.data = 'First removed. Second repeat.';
  expect(!run(f, 'repeat.', match)?.found && f.effects.scrolls === before, 'DOM mutation between lookup and effect cannot reuse an obsolete endpoint');
  f.document.body.firstChild.data = 'First repeat. Second repeat.';
  run(f, 'Second repeat.', null, 'new-operation');
  expect(!run(f, 'repeat.', match)?.found && f.effects.scrolls === before, 'a newer operation lease retires an old quote');
  const newDocument = fixture(({text: t}) => [t('First repeat. Second repeat.')]);
  expect(!run(newDocument, 'repeat.', match)?.found && newDocument.effects.scrolls === 0,
    'same-URL new document globals never authorize an old effect');
  run(f, 'repeat.');
  vm.runInContext(fs.readFileSync(process.argv[3], 'utf8'), f.context);
  expect(run(f, 'repeat.', match) === null && f.effects.scrolls === before, 'the production compare-and-clear retires the pending effect lease');
  f.context.__craAskQuote = parameters.lease;
  f.document.URL += '?changed';
  expect(!run(f, 'repeat.', match)?.found && f.effects.scrolls === before, 'a changed live URL cannot scroll');
}
// promise: #393
function boundedAndExcluded() {
  const f = fixture(({element: e, text: t}) => [e('NAV', [t('Navigation secret')]), e('INPUT', [t('Form secret')]),
    e('SPAN', [t('Hidden secret')], {hidden: ''}), t('Visible source sentence.')]);
  for (const q of ['Navigation secret', 'Form secret', 'Hidden secret']) expect(!run(f, q).found, 'excluded text cannot authorize a quote');
  find(f, 'Visible source sentence.');
  const enormous = fixture(({text: t}) => [t('x'.repeat(65537)), t('target')]);
  expect(run(enormous, 'target') === null && enormous.effects.scrolls === 0, 'oversized traversal fails closed without scanning an unbounded node');
  const wrongType = fixture(({text: t}) => [t('target')]); wrongType.document.contentType = 'application/pdf';
  expect(run(wrongType, 'target') === null, 'effects require genuine current HTML/XHTML');
}
function reachablePrefixOnLongDocuments() {
  const quote = 'The observatory opens at nine every morning.';
  const cases = [
    ({text: t}) => [t(quote + ' ' + 'x'.repeat(70000))],
    ({text: t}) => [t(quote), t('x'.repeat(70000))],
    ({text: t, element: e}) => [t(quote + ' '), ...Array.from({length: 13000}, () => e('SPAN', [], {hidden: ''})), t('Unreached target.')]
  ];
  for (const children of cases) {
    const f = fixture(children), lookup = run(f, quote);
    expect(lookup?.found, 'an exact early quote remains reachable before oversized text or later work exhaustion');
    expect(f.effects.scrolls === 0 && f.effects.selection === null, 'a bounded-prefix lookup has no page effects');
    expect(run(f, quote, lookup)?.found, 'a bounded-prefix effect revalidates and selects its exact current range');
    const selected = f.effects.selection;
    expect(selected.start[0] === selected.end[0] && selected.start[0].data.slice(selected.start[1], selected.end[1]) === quote,
      'the selected range contains the complete early quote rather than an unrelated prefix');
    expect(f.effects.largestRead <= 65536, 'no oversized text node is materialized past the existing UTF-16 ceiling');
    expect(run(f, 'Unreached target.') === null, 'a target beyond the bounded prefix stays unknown rather than not found');
    const scrolls = f.effects.scrolls;
    f.document.body.firstChild.data = 'The original early quote was removed. ' + 'x'.repeat(70000);
    expect(!run(f, quote, lookup)?.found && f.effects.scrolls === scrolls,
      'a changed early quote cannot reuse its old prefix endpoints or cause another effect');
  }
  const inline = fixture(({text: t, element: e}) => [t('The cafe'), e('EM', [t('\u0301 opens at nine.')]), t(' ' + 'x'.repeat(70000))]);
  find(inline, 'The café opens at nine.');
  expect(inline.effects.selection.start[0].data === 'The cafe' && inline.effects.selection.end[1] === '\u0301 opens at nine.'.length,
    'bounded-prefix NFC matching preserves exact endpoints across decomposed inline nodes');
}
function clippedGraphemesStayUnknown() {
  for (const [prefix, suffix, quote] of [
    ['x'.repeat(65535) + 'e', '\u0301 rest', 'e'],
    ['x'.repeat(65534) + '👩', '\u200d🔬 rest', '👩'],
    ['x'.repeat(65535) + '\ud83d', '\udc69 rest', '\ud83d']
  ]) {
    for (const split of [false, true]) {
      const f = fixture(({text: t}) => split ? [t(prefix), t(suffix)] : [t(prefix + suffix)]);
      expect(run(f, quote) === null && f.effects.scrolls === 0 && f.effects.selection === null,
        'a clipped or unvisited combining, ZWJ or surrogate continuation cannot authorize a partial grapheme');
    }
  }
  const unvisited = fixture(({text: t, element: e}) => [t('An unfinished cafe'),
    ...Array.from({length: 13000}, () => e('SPAN', [], {hidden: ''})), t('\u0301 continues.')]);
  expect(run(unvisited, 'An unfinished cafe') === null && unvisited.effects.scrolls === 0,
    'work exhaustion before a later inline combining continuation cannot certify the final collected grapheme');
}
literalInlineUnicode(); liveRevalidationAndLease(); boundedAndExcluded();
reachablePrefixOnLongDocuments(); clippedGraphemesStayUnknown();
console.log(`Ask quote DOM: ${checks} controlled script checks passed (no engine execution)`);
