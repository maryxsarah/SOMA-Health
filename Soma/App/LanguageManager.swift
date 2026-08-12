import Foundation
import SwiftUI

/// The languages Soma ships translations for. `.system` (the default)
/// follows the device's language; the picker lets a user override it.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es, fr, it, de, ru, ka, hy, sr

    var id: String { rawValue }

    /// `nil` for `.system` means "don't override" -- stays on the live
    /// device locale rather than freezing it at launch.
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }

    /// Each language's name written in itself, so a user who can't read
    /// the current language can still find their own. `.system` is the
    /// one case that IS translated, hence the explicit `locale:` param.
    func displayName(locale: Locale) -> String {
        switch self {
        case .system: localizedString("settings.language.system", locale: locale)
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        case .it: "Italiano"
        case .de: "Deutsch"
        case .ru: "Русский"
        case .ka: "ქართული"
        case .hy: "Հայերեն"
        case .sr: "Српски"
        }
    }

    /// Language code for AI-generation requests, so model output matches
    /// the UI language. Falls back to English if unsupported.
    var aiRequestCode: String {
        let resolved = (locale ?? Locale.autoupdatingCurrent).language.languageCode?.identifier ?? "en"
        return AppLanguage(rawValue: resolved) != nil ? resolved : "en"
    }
}

/// Owns the user's in-app language override. Applies live via
/// `.environment(\.locale, ...)`; `String(localized:)` picks it up next launch.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            UserDefaults.standard.set(selected.rawValue, forKey: Self.storageKey)
            if let code = selected.locale?.identifier {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            AnalyticsManager.shared.featureUsed(name: "language_override_\(selected.rawValue)")
        }
    }

    private static let storageKey = "com.soma.app.languageOverride"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        selected = AppLanguage(rawValue: stored) ?? .system
    }

    /// What to hand `.environment(\.locale, ...)` -- the device's live,
    /// auto-updating locale unless the user picked an explicit override.
    var effectiveLocale: Locale {
        selected.locale ?? .autoupdatingCurrent
    }
}

/// `String(localized:locale:)`'s explicit `locale:` didn't reliably
/// re-resolve in testing, so this loads the target `.lproj` bundle directly.
func localizedString(_ key: String, locale: Locale) -> String {
    let bundle = Bundle.main.path(forResource: locale.identifier, ofType: "lproj")
        .flatMap(Bundle.init(path:)) ?? .main
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
