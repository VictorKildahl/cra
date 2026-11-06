import CraCore
import Foundation
import Testing

/// Which extension's proxy Chromium applies, read from extensions.settings (GitHub #107).
struct ExtensionProxyControlTests {
    static func ext(_ time: String, proxy: [String: Any]?, key: String = "preferences") -> [String: Any] {
        var s: [String: Any] = ["last_update_time": time, "state": 1]
        if let proxy { s[key] = ["proxy": proxy] }
        return s
    }

    static let pac: [String: Any] = ["mode": "pac_script", "pac_url": "data:application/x-ns-proxy-autoconfig;base64,ZnVuY3Rpb24="]
    static let fixed: [String: Any] = ["mode": "fixed_servers", "server": "proxy.corp.example:3128", "bypass_list": "<local>"]

    /// The most recently installed or updated one wins; the other is overridden.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func latestInstallWins() {
        let settings: [String: Any] = [
            "zeroomega": Self.ext("13400000000000000", proxy: Self.pac),
            "otherproxy": Self.ext("13400000000000500", proxy: Self.fixed),
            "noproxy": Self.ext("13400000000009999", proxy: nil),
        ]
        let c = ExtensionProxyControl.controllers(settings: settings, enabled: ["zeroomega", "otherproxy", "noproxy"])
        #expect(c.map(\.extensionID) == ["otherproxy", "zeroomega"])
        #expect(c[0].config == "fixed_servers proxy.corp.example:3128")
        #expect(c[0].hosts == ["proxy.corp.example"] && c[1].hosts.isEmpty)
        #expect(c[1].config == "pac_script (inline)")
    }

    /// A turned-off or uninstalled extension's leftover pref does not count.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func onlyEnabledExtensionsCount() {
        let settings: [String: Any] = [
            "a": Self.ext("100", proxy: Self.pac),
            "b": Self.ext("200", proxy: Self.fixed),
        ]
        #expect(ExtensionProxyControl.controllers(settings: settings, enabled: ["a"]).map(\.extensionID) == ["a"])
        #expect(ExtensionProxyControl.controllers(settings: settings, enabled: []).isEmpty)
    }

    /// Chromium's map walks IDs in order and a later equal time takes over.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func tieGoesToTheLaterID() {
        let settings: [String: Any] = ["aaa": Self.ext("100", proxy: Self.pac), "bbb": Self.ext("100", proxy: Self.fixed)]
        #expect(ExtensionProxyControl.controllers(settings: settings, enabled: ["aaa", "bbb"]).first?.extensionID == "bbb")
    }

    /// chrome.proxy.settings.set with scope "regular_only".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func regularOnlyScopeCounts() {
        let settings: [String: Any] = ["a": Self.ext("100", proxy: Self.fixed, key: "regular_only_preferences"),
                                       "b": Self.ext("50", proxy: Self.pac, key: "incognito_preferences")]
        #expect(ExtensionProxyControl.controllers(settings: settings, enabled: ["a", "b"]).map(\.extensionID) == ["a"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"), arguments: [
        (["mode": "direct"], "direct"),
        (["mode": "system"], "system"),
        (["mode": "auto_detect"], "auto_detect"),
        (["mode": "pac_script", "pac_url": "https://wpad.corp.example/secret/proxy.pac?token=1"], "pac_script wpad.corp.example"),
        (["mode": "pac_script"], "pac_script (inline)"),
        (["mode": "fixed_servers", "server": "http=h1:80;https=h2:443"], "fixed_servers http=h1:80;https=h2:443"),
        (["mode": "fixed_servers", "server": "socks5://user:pw@s.example:1080"], "fixed_servers socks5://s.example:1080"),
    ] as [([String: String], String)])
    func summaries(proxy: [String: String], expected: String) {
        #expect(ExtensionProxyControl.summary(proxy) == expected)
    }
}
