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
          if (exit) { if (leave && leave(node, block) === false) return false; continue; }
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
        return AskOnPagePolicy.canAsk(page: URL(string: url))
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
