// Executes the production generated script against a small, controlled DOM surface. No browser engine proof.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const script = fs.readFileSync(process.argv[2], 'utf8').trim(), cut = script.lastIndexOf('})(');
const parameters = JSON.parse(script.slice(cut + 3, -1));
let checks = 0;
function expect(value, message) { assert.ok(value, message); checks++; }
function fixture(children) {
  const effects = {selection: null, scrolls: 0};
  const document = {URL: parameters.url, contentType: 'text/html'};
  function element(tag, children = [], attributes = {}, display = 'inline') {
    return {nodeType: 1, tagName: tag, children, display, attributes,
      hasAttribute(key) { return key in this.attributes; }, getAttribute(key) { return this.attributes[key] ?? null; },
      scrollIntoView() { effects.scrolls++; }};
  }
  function text(data) { return {nodeType: 3, data, get length() { return this.data.length; }, substringData(a, b) { return this.data.slice(a, a + b); }}; }
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
literalInlineUnicode(); liveRevalidationAndLease(); boundedAndExcluded();
console.log(`Ask quote DOM: ${checks} controlled script checks passed (no engine execution)`);
