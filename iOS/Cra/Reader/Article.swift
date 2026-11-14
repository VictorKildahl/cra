import CraCore
import UIKit
import WebKit

/// A page's article: what Reader shows and what Summarize reads.
struct Article {
    var title: String
    var byline: String
    var site: String
    /// The article's markup, reduced to text structure, links and pictures.
    var html: String
    var text: String

    /// Reads the article out of a live page: the element holding the most paragraph text, without
    /// navigation, forms, scripts and the like.
    static func extract(from webView: WKWebView, done: @escaping (Article?) -> Void) {
        webView.evaluateJavaScript(script) { value, _ in
            guard let fields = value as? [String: String], let text = fields["text"], let html = fields["html"] else { return done(nil) }
            done(Article(title: fields["title"] ?? "", byline: fields["byline"] ?? "", site: fields["site"] ?? "", html: html, text: text))
        }
    }

    private static let script = """
    (() => {
      const paragraphs = el => [...el.querySelectorAll('p')].reduce((n, p) => n + Math.min(p.innerText.length, 600), 0);
      let best = null, bestScore = 0;
      for (const el of document.querySelectorAll('article, main, [role=main], [itemprop=articleBody], .post-content, .article-body, .entry-content, #content')) {
        const score = paragraphs(el);
        if (score > bestScore) { best = el; bestScore = score; }
      }
      if (!best || bestScore < 400) {
        for (const el of document.querySelectorAll('div, section')) {
          const own = [...el.children].filter(c => c.tagName === 'P').reduce((n, p) => n + p.innerText.length, 0);
          if (own > bestScore) { best = el; bestScore = own; }
        }
      }
      best = best || document.body;
      const junk = 'script, style, noscript, iframe, form, nav, aside, footer, button, input, select, textarea, svg, video, audio, [aria-hidden=true], [role=navigation], [role=complementary], .ad, .ads, .advert, .advertisement, .share, .social, .related, .newsletter, .comments, .sidebar';
      const text = (() => { const copy = best.cloneNode(true); copy.querySelectorAll(junk).forEach(n => n.remove()); const holder = document.createElement('div'); holder.style.cssText = 'position:absolute;left:-99999px;width:600px'; holder.appendChild(copy); document.body.appendChild(holder); const t = copy.innerText; holder.remove(); return t; })();
      const root = best.cloneNode(true);
      root.querySelectorAll(junk).forEach(n => n.remove());
      const allowed = new Set(['P','H1','H2','H3','H4','H5','H6','UL','OL','LI','BLOCKQUOTE','PRE','CODE','EM','STRONG','B','I','U','A','IMG','FIGURE','FIGCAPTION','BR','HR','TABLE','THEAD','TBODY','TR','TD','TH','SUP','SUB']);
      const clean = node => {
        for (const child of [...node.children]) {
          clean(child);
          if (!allowed.has(child.tagName)) { child.replaceWith(...child.childNodes); continue; }
          const href = child.tagName === 'A' ? child.href : null;
          const src = child.tagName === 'IMG' ? (child.currentSrc || child.src) : null;
          const alt = child.tagName === 'IMG' ? child.alt : null;
          for (const a of [...child.attributes]) child.removeAttribute(a.name);
          if (href && /^https?:/.test(href)) child.setAttribute('href', href);
          if (src && /^https?:/.test(src)) { child.setAttribute('src', src); if (alt) child.setAttribute('alt', alt); }
          else if (child.tagName === 'IMG') child.remove();
        }
      };
      clean(root);
      const meta = name => (document.querySelector(`meta[property="${name}"], meta[name="${name}"]`) || {}).content || '';
      const heading = document.querySelector('h1');
      return {
        title: meta('og:title') || (heading && heading.innerText) || document.title || '',
        byline: meta('author') || meta('article:author') || '',
        site: location.hostname.replace(/^www\\./, ''),
        html: root.innerHTML,
        text: text || ''
      };
    })()
    """

    /// The article as a page of its own: no scripts, the device's serif, light and dark.
    var readerHTML: String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let meta = [byline, site].filter { !$0.isEmpty }.map(escape).joined(separator: " · ")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; padding: 28px 22px 120px; font: 19px/1.62 ui-serif, "New York", Georgia, serif; color: #1c1c1e; background: #fbfaf8; -webkit-text-size-adjust: 100%; }
        main { max-width: 680px; margin: 0 auto; }
        h1.title { font: 700 29px/1.2 ui-serif, "New York", Georgia, serif; margin: 0 0 10px; }
        .meta { font: 14px -apple-system, sans-serif; color: #8a8a8e; margin: 0 0 26px; }
        h1, h2, h3, h4 { line-height: 1.25; margin: 1.5em 0 0.5em; }
        h2 { font-size: 23px; } h3 { font-size: 20px; }
        p { margin: 0 0 1.05em; }
        a { color: #3f6df5; text-decoration: none; }
        img { max-width: 100%; height: auto; border-radius: 10px; margin: 0.4em 0; }
        figure { margin: 1.2em 0; } figcaption { font: 14px -apple-system, sans-serif; color: #8a8a8e; }
        blockquote { margin: 1.2em 0; padding-left: 16px; border-left: 3px solid #c9c6cf; color: #55545a; }
        pre { overflow-x: auto; font: 14px ui-monospace, Menlo, monospace; background: rgba(0,0,0,0.05); padding: 12px; border-radius: 10px; }
        table { border-collapse: collapse; display: block; overflow-x: auto; } td, th { border: 1px solid #d0d0d4; padding: 6px 9px; font-size: 16px; }
        @media (prefers-color-scheme: dark) {
          body { color: #ececee; background: #1c1c1e; } .meta, figcaption { color: #98989e; }
          a { color: #7f9dff; } blockquote { border-left-color: #48484c; color: #b0b0b6; } pre { background: rgba(255,255,255,0.08); } td, th { border-color: #48484c; }
        }
        </style></head><body><main>
        <h1 class="title">\(escape(title))</h1>
        \(meta.isEmpty ? "" : "<p class=\"meta\">\(meta)</p>")
        \(html)
        </main></body></html>
        """
    }
}

/// Reader: the article alone, over its page. Scripts are off in here; a tapped link leaves
/// Reader and goes to the link in the tab.
final class ReaderView: UIView, WKNavigationDelegate {
    private let webView: WKWebView
    var onLink: ((URL) -> Void)?

    init(article: Article) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        backgroundColor = Palette.dynamic(light: Palette.rgb(0xfbfaf8), dark: Palette.rgb(0x1c1c1e))
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.accessibilityIdentifier = "reader"
        addSubview(webView)
        webView.loadHTMLString(article.readerHTML, baseURL: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            onLink?(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
    }
}
