import Foundation

/// Translate in the page menu (Arc Search 1.19). Arc Search sends the page to Google Translate;
/// Cra translates on the phone with Apple's Translation framework, so the page never leaves it.
/// The page's visible text is collected node by node, translated in batches, and written back;
/// the originals are kept on the page so "Show Original" puts them back without a reload.
public enum MobileTranslate {
    /// Most characters in one batch handed to the translator.
    public static let batchCharacters = 4000
    /// Text nodes beyond this many are left as they are (a very long page).
    public static let nodeLimit = 3000

    /// Collects the page's visible text: every text node with letters in it, outside scripts,
    /// styles, code and form fields, in document order. Returns the texts (whitespace trimmed);
    /// the nodes stay in `window.__craTranslation` for `applyScript`.
    public static let collectScript = """
    (() => {
      const skip = new Set(['SCRIPT','STYLE','NOSCRIPT','TEXTAREA','INPUT','SELECT','OPTION','CODE','PRE','KBD','SAMP','SVG','MATH','TEMPLATE','IFRAME']);
      const state = window.__craTranslation || { nodes: [], originals: [] };
      if (state.translated) { return state.nodes.map((n, i) => state.originals[i].trim()); }
      const nodes = [];
      const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
        acceptNode(node) {
          if (!/\\p{L}/u.test(node.nodeValue)) return NodeFilter.FILTER_REJECT;
          for (let el = node.parentElement; el; el = el.parentElement) {
            if (skip.has(el.tagName) || el.isContentEditable || el.getAttribute('translate') === 'no' || el.classList.contains('notranslate')) return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      while (walker.nextNode() && nodes.length < \(nodeLimit)) nodes.push(walker.currentNode);
      window.__craTranslation = { nodes, originals: nodes.map(n => n.nodeValue), translated: false };
      return nodes.map(n => n.nodeValue.trim());
    })()
    """

    /// Writes `translations` (one per collected text, in order) into the page, keeping each
    /// node's own leading and trailing whitespace.
    public static func applyScript(_ translations: [String]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: translations)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        (() => {
          const state = window.__craTranslation; if (!state) return 0;
          const out = \(json);
          state.nodes.forEach((node, i) => {
            if (i >= out.length || out[i] == null) return;
            const original = state.originals[i];
            const lead = original.match(/^\\s*/)[0], trail = original.match(/\\s*$/)[0];
            node.nodeValue = lead + out[i] + trail;
          });
          state.translated = true;
          return out.length;
        })()
        """
    }

    /// Puts the page's own words back.
    public static let restoreScript = """
    (() => {
      const state = window.__craTranslation; if (!state) return 0;
      state.nodes.forEach((node, i) => { node.nodeValue = state.originals[i]; });
      state.translated = false;
      return state.nodes.length;
    })()
    """

    /// The texts' indices in batches of at most `maxCharacters` (a longer text is a batch of its own).
    public static func batches(_ texts: [String], maxCharacters: Int = batchCharacters) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        var size = 0
        for (index, text) in texts.enumerated() {
            if !current.isEmpty, size + text.count > maxCharacters {
                result.append(current)
                current = []
                size = 0
            }
            current.append(index)
            size += text.count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A sample of the page's text to tell its language by: the longest texts first, up to `limit` characters.
    public static func languageSample(_ texts: [String], limit: Int = 2000) -> String {
        var sample = ""
        for text in texts.sorted(by: { $0.count > $1.count }) {
            guard sample.count < limit else { break }
            sample += text + " "
        }
        return String(sample.prefix(limit))
    }
}
