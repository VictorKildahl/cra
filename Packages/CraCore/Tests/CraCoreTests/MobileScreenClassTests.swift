import CoreGraphics
import CraCore
import Testing

/// The open iPhone Duo treated like a small iPad (#866, Victor's call on 0xJeu's proposal, 27 Nov 2026).
struct MobileScreenClassTests {
    let openDuo = CGSize(width: 951, height: 669), closedDuo = CGSize(width: 466, height: 678)
    let iPhone = CGSize(width: 393, height: 852), iPhoneOnItsSide = CGSize(width: 874, height: 402)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/866"))
    func onlyTheOpenDuoIsWide() {
        #expect(MobileScreenClass.of(size: openDuo, isPad: false) == .wide)
        for size in [closedDuo, iPhone, iPhoneOnItsSide] { #expect(MobileScreenClass.of(size: size, isPad: false) == .phone) }
        #expect(MobileScreenClass.of(size: CGSize(width: 1180, height: 820), isPad: true) == .pad)
    }

    /// 1: App Settings and the App Icon picker open at full height on the open Duo, as on iPad.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/866"))
    func sheetsOpenFullAsOnIPad() {
        let wide = MobileScreenClass.of(size: openDuo, isPad: false)
        #expect(MobileSettingsSheet.appSettingsHeights(onPad: wide.opensSheetsFull) == [.large])
        #expect(MobileSettingsSheet.appSettingsHeights(onPad: MobileScreenClass.phone.opensSheetsFull) == [.medium, .large])
    }

    /// 2: the bottom bar's buttons keep within 540 pt in the middle of the open Duo, not at its far edges; phones and iPads
    /// keep theirs where they were.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/866"))
    func theBarsButtonsKeepToTheMiddle() {
        let wide = MobileBottomBar.frames(in: openDuo, safeBottom: 20, band: MobileScreenClass.wide.barBand)
        let left = (951 - 540) / 2.0
        #expect(abs(wide.tabs.midX - (left + MobileBottomBar.sideButtonCenterInset)) < 0.001)
        #expect(abs(wide.menu.midX - (left + 540 - MobileBottomBar.sideButtonCenterInset)) < 0.001)
        #expect(abs(wide.pill.midX - 951 / 2.0) < 0.001)
        for cls in [MobileScreenClass.phone, .pad] {
            #expect(MobileBottomBar.frames(in: iPhone, safeBottom: 34, band: cls.barBand) == MobileBottomBar.frames(in: iPhone, safeBottom: 34))
        }
    }

    /// 3: the tab row stays a carousel, laid out as on the widest iPhone in the middle of the open Duo, so its card is
    /// phone-sized (305 pt, not 660) and the neighbours show.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/866"))
    func theTabRowIsPhoneSizedInTheMiddle() {
        let insets = MobileScreenClass.wide.carouselInsets(size: openDuo, insets: (0, 0))
        #expect(insets.left == (951 - 440) / 2.0 && insets.right == insets.left)
        let focus = MobileTabCarousel.placement(relative: 0, in: openDuo, sideInsets: insets)
        #expect(focus.frame.width == (440 * MobileTabCarousel.cardScale).rounded())
        #expect(MobileScreenClass.phone.carouselInsets(size: iPhone, insets: (0, 0)) == (0, 0))
        #expect(MobileScreenClass.phone.carouselInsets(size: closedDuo, insets: (0, 47)) == (0, 47))
    }
}
