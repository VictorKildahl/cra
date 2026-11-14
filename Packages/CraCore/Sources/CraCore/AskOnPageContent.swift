import Foundation

/// Reads the current document, never a second URL request. Both traversal and returned data are bounded.
public enum AskOnPageContent {
    public static let script = #"""
    (() => {
      if (!document.body || !['text/html', 'application/xhtml+xml'].includes(document.contentType)) return null;
      const excluded = new Set(['SCRIPT', 'STYLE', 'SVG', 'NOSCRIPT', 'TEMPLATE', 'NAV', 'HEADER', 'FOOTER',
        'INPUT', 'TEXTAREA', 'SELECT', 'OPTION', 'BUTTON', 'IFRAME', 'OBJECT', 'EMBED']);
      const blocks = new Set(['block', 'flow-root', 'flex', 'grid', 'list-item', 'table', 'table-row',
        'table-row-group', 'table-header-group', 'table-footer-group', 'table-caption', 'table-cell']);
      const display = node => {
        if (node.nodeType !== 1) return '';
        if (excluded.has(node.tagName) || node.hasAttribute('hidden') || node.getAttribute('aria-hidden') === 'true') return null;
        const style = getComputedStyle(node);
        if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse') return null;
        return style.display;
      };
      // Schedule one sibling at a time: a huge childNodes collection is never copied or enumerated first.
      const walk = (root, budget, visit, leave) => {
        const stack = [{node: root, exit: false}];
        let work = 0;
        while (stack.length) {
          if (++work > budget) return false;
          const {node, exit, block} = stack.pop();
          if (exit) { if (leave) leave(node, block); continue; }
          if (node !== root && node.nextSibling) stack.push({node: node.nextSibling, exit: false});
          const layout = display(node);
          if (layout === null) continue;
          const boundary = blocks.has(layout) || layout.startsWith('block ');
          if (visit(node, boundary) === false) return false;
          if (leave) stack.push({node, exit: true, block: boundary});
          if (node.firstChild) stack.push({node: node.firstChild, exit: false});
        }
        return true;
      };
      let root = document.body;
      walk(root, 2000, node => {
        if (node.nodeType === 1 && (node.tagName === 'MAIN' || node.tagName === 'ARTICLE' || node.getAttribute('role') === 'main')) {
          root = node; return false;
        }
      });
      // 16,384 UTF-16 units use at most 49,152 UTF-8 bytes, below the native 64 KiB text ceiling.
      const maximumUnits = 16384;
      let text = '', truncated = false;
      const newline = () => { if (text && !text.endsWith('\n') && text.length < maximumUnits) text += '\n'; };
      const complete = walk(root, 12000, (node, block) => {
        if (node.nodeType === 1) { if (block || node.tagName === 'BR') newline(); return; }
        if (node.nodeType !== 3) return;
        const remaining = maximumUnits - text.length;
        if (remaining <= 0) return false;
        // substringData avoids materializing an arbitrarily large text node before taking its prefix.
        let piece = node.substringData(0, Math.min(node.length, remaining));
        if (piece.length < node.length) {
          // The last segment might have been cut in the middle, even when its last scalar is complete.
          let last = 0;
          for (const segment of new Intl.Segmenter(undefined, {granularity: 'grapheme'}).segment(piece)) last = segment.index;
          piece = piece.slice(0, last);
          truncated = true;
        }
        text += piece;
        if (truncated) return false;
      }, (node, block) => { if (block) newline(); });
      return {url: document.URL.slice(0, 8192), title: document.title.slice(0, 1024), text: text.trim(),
        contentType: document.contentType, truncated: truncated || !complete};
    })()
    """#

    /// Only a successful by-value HTML response for the exact captured document can become context.
    public static func page(evaluation: String?, expectedURL: String) -> AskOnPagePrompt.Page? {
        guard let evaluation, evaluation.utf8.count <= 300_000, supportsURL(expectedURL),
              let response = try? JSONDecoder().decode(Evaluation.self, from: Data(evaluation.utf8)),
              let value = response.result.value, value.url == expectedURL,
              ["text/html", "application/xhtml+xml"].contains(value.contentType),
              value.url.utf8.count <= 8192, value.title.utf8.count <= 4096, value.text.utf8.count <= 65_536,
              AskOnPage.normalized(value.text).count >= 50 else { return nil }
        return .init(url: value.url, title: value.title, text: value.text, wasTruncated: value.truncated)
    }

    public static func supportsURL(_ url: String) -> Bool {
        guard url.utf8.count <= 8192 else { return false }
        return AskOnPagePolicy.supportsURL(URL(string: url))
    }

    private struct Evaluation: Decodable {
        struct Remote: Decodable { let value: Value? }
        struct Value: Decodable {
            let url: String
            let title: String
            let text: String
            let contentType: String
            let truncated: Bool
        }
        let result: Remote
        enum CodingKeys: String, CodingKey { case result, exceptionDetails }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard !c.contains(.exceptionDetails) else {
                throw DecodingError.dataCorruptedError(forKey: .exceptionDetails, in: c, debugDescription: "Page evaluation failed")
            }
            result = try c.decode(Remote.self, forKey: .result)
        }
    }
}

/// Bounded literal quote lookup. A lookup has no effects; effects rebuild the live range from scratch.
public enum AskOnPageQuoteDOM {
    public struct Match: Codable, Equatable, Sendable {
        public let startNode: Int
        public let startOffset: Int
        public let endNode: Int
        public let endOffset: Int
    }
    public enum Lookup: Equatable { case notFound, match(Match) }

    public static func lookup(_ quote: String, url: String, lease: UUID) -> String {
        expression(quote, url: url, lease: lease, match: nil)
    }

    public static func effect(_ quote: String, url: String, lease: UUID, match: Match) -> String {
        expression(quote, url: url, lease: lease, match: match)
    }

    public static func result(_ evaluation: String?) -> Lookup? {
        guard let value = value(evaluation) else { return nil }
        if !value.found { return .notFound }
        guard let start = value.startNode, let startOffset = value.startOffset,
              let end = value.endNode, let endOffset = value.endOffset,
              (0..<12000).contains(start), (start..<12000).contains(end),
              (0...65536).contains(startOffset), (0...65536).contains(endOffset),
              start != end || startOffset < endOffset else { return nil }
        return .match(Match(startNode: start, startOffset: startOffset, endNode: end, endOffset: endOffset))
    }

    public static func retire(_ lease: UUID) -> String {
        "if (globalThis.__craAskQuote === '\(lease.uuidString)') globalThis.__craAskQuote = null;"
    }

    public static func effected(_ evaluation: String?) -> Bool? { value(evaluation)?.found }

    private struct Value: Decodable {
        let found: Bool
        let startNode: Int?, startOffset: Int?, endNode: Int?, endOffset: Int?
    }
    private struct Evaluation: Decodable {
        struct Remote: Decodable { let value: Value? }
        let result: Remote
        enum CodingKeys: String, CodingKey { case result, exceptionDetails }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard !c.contains(.exceptionDetails) else {
                throw DecodingError.dataCorruptedError(forKey: .exceptionDetails, in: c, debugDescription: "Quote evaluation failed")
            }
            result = try c.decode(Remote.self, forKey: .result)
        }
    }
    private static func value(_ evaluation: String?) -> Value? {
        guard let evaluation, evaluation.utf8.count <= 1024 else { return nil }
        return (try? JSONDecoder().decode(Evaluation.self, from: Data(evaluation.utf8)))?.result.value
    }

    private static func expression(_ quote: String, url: String, lease: UUID, match: Match?) -> String {
        let parameters: [String: Any] = ["quote": AskOnPage.normalized(quote), "url": url, "lease": lease.uuidString,
            "match": match.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()]
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: parameters), as: UTF8.self)
        return "(p => {\n" + body + "\n})(" + json + ")"
    }

    private static let body = #"""
      if (document.URL !== p.url || !document.body ||
          !['text/html', 'application/xhtml+xml'].includes(document.contentType) ||
          !p.quote || p.quote.length > 8192 || typeof Intl.Segmenter !== 'function') return null;
      if (p.match && globalThis.__craAskQuote !== p.lease) return null;
      if (!p.match) globalThis.__craAskQuote = p.lease;
      const excluded = new Set(['SCRIPT', 'STYLE', 'SVG', 'NOSCRIPT', 'TEMPLATE', 'NAV', 'HEADER', 'FOOTER',
        'INPUT', 'TEXTAREA', 'SELECT', 'OPTION', 'BUTTON', 'IFRAME', 'OBJECT', 'EMBED']);
      const blocks = new Set(['block', 'flow-root', 'flex', 'grid', 'list-item', 'table', 'table-row',
        'table-row-group', 'table-header-group', 'table-footer-group', 'table-caption', 'table-cell']);
      const nodes = [], spans = [], stack = [{node: document.body, exit: false}];
      let raw = '', work = 0;
      const boundary = () => { if (raw && !raw.endsWith('\n')) raw += '\n'; };
      while (stack.length) {
        if (++work > 12000 || raw.length > 65536) return null;
        const {node, exit, block} = stack.pop();
        if (exit) { if (block) boundary(); continue; }
        if (node !== document.body && node.nextSibling) stack.push({node: node.nextSibling, exit: false});
        let isBlock = false;
        if (node.nodeType === 1) {
          if (excluded.has(node.tagName) || node.hasAttribute('hidden') || node.getAttribute('aria-hidden') === 'true') continue;
          const style = getComputedStyle(node);
          if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse') continue;
          isBlock = blocks.has(style.display) || style.display.startsWith('block ');
          if (isBlock || node.tagName === 'BR') boundary();
        } else if (node.nodeType === 3) {
          if (node.length > 65536 - raw.length) return null;
          const index = nodes.length;
          nodes.push(node); spans.push({index, start: raw.length, end: raw.length + node.length});
          raw += node.substringData(0, node.length);
        }
        stack.push({node, exit: true, block: isBlock});
        if (node.firstChild) stack.push({node: node.firstChild, exit: false});
      }
      // Normalize complete graphemes, including combining sequences split across inline nodes.
      // Each normalized UTF-16 boundary maps back to the original DOM text, never transport spelling.
      let text = '', pendingSpace = false;
      const starts = new Map(), ends = new Map();
      for (const part of new Intl.Segmenter(undefined, {granularity: 'grapheme'}).segment(raw)) {
        const piece = part.segment.normalize('NFC'), end = part.index + part.segment.length;
        if (/^\p{White_Space}+$/u.test(piece)) { pendingSpace = true; continue; }
        if (pendingSpace && text) text += ' ';
        pendingSpace = false;
        starts.set(text.length, part.index);
        text += piece;
        ends.set(text.length, end);
      }
      let at = text.indexOf(p.quote);
      while (at >= 0 && (!starts.has(at) || !ends.has(at + p.quote.length))) at = text.indexOf(p.quote, at + 1);
      if (at < 0) return {found: false};
      const start = starts.get(at), end = ends.get(at + p.quote.length);
      const a = spans.find(s => start >= s.start && start < s.end);
      const b = spans.find(s => end > s.start && end <= s.end);
      if (!a || !b) return {found: false};
      const match = {startNode: a.index, startOffset: start - a.start, endNode: b.index, endOffset: end - b.start};
      if (!p.match) return {found: true, ...match};
      if (!Object.keys(match).every(key => match[key] === p.match[key])) return {found: false};
      const first = nodes[a.index], last = nodes[b.index];
      if (!first.isConnected || !last.isConnected || first.ownerDocument !== document || last.ownerDocument !== document) return {found: false};
      if (globalThis.__craAskQuote !== p.lease || document.URL !== p.url) return null;
      const range = document.createRange();
      range.setStart(first, match.startOffset); range.setEnd(last, match.endOffset);
      const selection = getSelection();
      if (!selection || range.collapsed || !range.getClientRects().length) return {found: false};
      // No await/callback between the fresh traversal, endpoint validation and effects.
      selection.removeAllRanges(); selection.addRange(range);
      first.parentElement.scrollIntoView({block: 'center', inline: 'nearest', behavior: 'instant'});
      return {found: true};
    """#
}
