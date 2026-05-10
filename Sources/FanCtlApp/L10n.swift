import Foundation
import SwiftUI

/// Localization accessor. Reads from the SwiftPM module bundle's
/// Localizable.strings (en.lproj is the canonical reference; es.lproj is
/// translated). Use `L10n.foo()` for runtime strings and `Text(L10n.foo)`
/// for SwiftUI views — the SwiftUI initializer takes `LocalizedStringKey`
/// directly.
enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static func text(_ key: String) -> Text {
        Text(LocalizedStringKey(key), bundle: .module)
    }

    // MARK: - Modes

    static func modeName(_ mode: String) -> String       { string("mode.\(mode)") }
    static func modeSummary(_ mode: String) -> String    { string("mode.summary.\(mode)") }

    // MARK: - About card

    static let aboutTagline    = "about.tagline"
    static let aboutCreatedBy  = "about.created"
    static let aboutSource     = "about.source"
    static let aboutPrefs      = "about.preferences"
    static let aboutUpdateCheck    = "about.update.check"
    static let aboutUpdateChecking = "about.update.checking"
    static let aboutLicense    = "about.license"

    // MARK: - Hero / labels

    static let heroRpm     = "hero.rpm"
    static let heroHottest = "hero.hottest"
    static let heroTarget  = "hero.target"
    static let heroMin     = "hero.min"
    static let heroMax     = "hero.max"

    // MARK: - Banner + install

    static let outdatedTitle   = "outdated.title"
    static let outdatedBody    = "outdated.body"
    static let outdatedRestart = "outdated.restart"
    static let outdatedCopy    = "outdated.copy"
    static let outdatedCopied  = "outdated.copied"

    static let installTitle    = "install.title"
    static let installBody     = "install.body"
    static let installButton   = "install.button"
    static let installRetry    = "install.retry"

    static let footerQuit      = "footer.quit"
    static let footerAuto      = "footer.auto"

    static let tempsTitle      = "temps.title"
}
