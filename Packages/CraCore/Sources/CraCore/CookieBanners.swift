import Foundation

/// Arc's Settings ▸ General "Block Cookie Banners" (off by default, Arc 1.172.1). Cra's blocker
/// filters requests by domain, so banners are hidden instead: the consent managers most sites use,
/// by the containers they put on the page, and the scroll lock some of them set while showing.
public enum CookieBanners {
    /// The banners' containers (OneTrust, Cookiebot, Didomi, Quantcast, TrustArc, Usercentrics,
    /// CookieYes, Osano, iubenda, Complianz, Termly, Sourcepoint, Klaro, Borlabs, Axeptio, Google's
    /// Funding Choices, CookieConsent).
    public static let selectors = [
        "#onetrust-banner-sdk", "#onetrust-consent-sdk", "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
        "#didomi-host", ".qc-cmp2-container", "#qc-cmp2-container", "#truste-consent-track", ".truste_overlay",
        ".truste_box_overlay", "#usercentrics-root", "#usercentrics-cmp-ui", ".cky-consent-container", ".cky-overlay",
        ".osano-cm-window", "#iubenda-cs-banner", "#cmplz-cookiebanner-container", ".cmplz-cookiebanner", "#termly-code-snippet-support",
        "[id^=\"sp_message_container\"]", ".klaro .cookie-notice", "#BorlabsCookieBox", "#axeptio_overlay",
        ".fc-consent-root", ".cc-window", ".cc-banner", "#cookie-law-info-bar", "#cookie-notice",
    ]

    /// The stylesheet a page gets: the banners hidden, scrolling back where a banner locked it.
    public static let css: String = {
        let hide = selectors.joined(separator: ", ") + " { display: none !important; visibility: hidden !important; }"
        let unlock = "html.sp-message-open, body.didomi-popup-open, body.cmplz-blocked-content, body.cky-modal-open, "
            + "body.onetrust-consent-sdk-open { overflow: auto !important; position: static !important; }"
        return hide + " " + unlock
    }()
}
