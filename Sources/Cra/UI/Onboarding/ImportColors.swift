import SwiftUI

/// The import window's colours, from Dia 1.54's asset catalogs (see ImportMetrics).
struct ImportColors {
    let dark: Bool
    var background: Color { dark ? .black : .white }
    /// RebrandAppTitleText
    var title: Color { dark ? .white.opacity(0.85) : .black.opacity(0.85) }
    /// RebrandBodyText
    var body: Color { dark ? .white.opacity(0.55) : .black.opacity(0.55) }
    var ink: Color { dark ? .white : .black }
    /// Browser card hairline: #5E5E5E / #9D9D9D over black.
    var cardBorder: Color { dark ? .white.opacity(0.37) : .black.opacity(0.14) }
    var cardBorderSelected: Color { dark ? .white.opacity(0.62) : .black.opacity(0.42) }
    /// BrowserItemBackground (hover)
    var cardHover: Color { dark ? .white.opacity(0.04) : .black.opacity(0.04) }
    /// Radio ring: #505050 over black.
    var radioRing: Color { dark ? .white.opacity(0.31) : .black.opacity(0.22) }
    /// RebrandRowBackground / RebrandRowBorder
    var rowFill: Color { dark ? .white.opacity(0.08) : .black.opacity(0.015) }
    var rowFillHover: Color { dark ? .white.opacity(0.11) : .black.opacity(0.04) }
    var rowBorder: Color { dark ? .white.opacity(0.16) : .black.opacity(0.08) }
    /// ImportSelectionCaption
    var caption: Color { dark ? .white.opacity(0.4) : .black.opacity(0.3) }
    /// ButtonPrimaryBackground: #E0E0E0 over black.
    var primaryFill: Color { dark ? Color(white: 0.878) : .black.opacity(0.85) }
    var primaryFillHover: Color { dark ? Color(white: 0.92) : .black.opacity(0.9) }
    var primaryText: Color { dark ? .black : .white }
    var primaryTextDisabled: Color { dark ? Color(white: 0.5) : .white.opacity(0.5) }
    /// ButtonDefaultBackground
    var secondaryFill: Color { dark ? .white.opacity(0.08) : .black.opacity(0.08) }
    var secondaryFillHover: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    /// ImportProgressItemBorder
    var tileBorder: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    /// LoadingSubtitle
    var loading: Color { dark ? .white.opacity(0.4) : .black.opacity(0.3) }
}
