import Foundation

struct VoiceEngineLanguage: Identifiable, Equatable {
    let id: String
    let displayName: String
    let aliases: [String]
    let isPopular: Bool

    var popularDisplayName: String {
        self.id == "zh" ? "Mandarin" : self.displayName
    }
}

struct VoiceEngineLanguageRoute: Identifiable, Equatable {
    enum LanguageBinding: Equatable {
        case automatic
        case appleSpeech(localeIdentifier: String)

        var id: String {
            switch self {
            case .automatic:
                return "auto"
            case let .appleSpeech(localeIdentifier):
                return "apple-\(localeIdentifier)"
            }
        }
    }

    let language: VoiceEngineLanguage
    let model: SettingsStore.SpeechModel
    let binding: LanguageBinding

    var id: String {
        "\(self.language.id)-\(self.model.rawValue)-\(self.binding.id)"
    }

    var badgeText: String? {
        switch self.model {
        case .parakeetTDTv2:
            return "Optimized for Speech2Write"
        default:
            return nil
        }
    }
}

enum VoiceEngineLanguageCatalog {
    static func allLanguages(
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels
    ) -> [VoiceEngineLanguage] {
        self.languageDefinitions.filter { language in
            !Self.routes(for: language, availableModels: availableModels).isEmpty
        }
    }

    static func popularLanguages(
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels
    ) -> [VoiceEngineLanguage] {
        self.allLanguages(availableModels: availableModels).filter(\.isPopular)
    }

    static func searchableLanguages(
        query: String,
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels
    ) -> [VoiceEngineLanguage] {
        let languages = Self.allLanguages(availableModels: availableModels)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return languages }

        return languages.filter { language in
            language.displayName.lowercased().contains(normalizedQuery) ||
                language.id.lowercased().contains(normalizedQuery) ||
                language.aliases.contains { $0.lowercased().contains(normalizedQuery) }
        }
    }

    static func language(
        id: String,
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels
    ) -> VoiceEngineLanguage? {
        self.allLanguages(availableModels: availableModels).first { $0.id == id }
    }

    static func routes(
        for language: VoiceEngineLanguage,
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels
    ) -> [VoiceEngineLanguageRoute] {
        self.routeCandidates(for: language).filter { route in
            availableModels.contains(route.model)
        }
    }

    static func routes(
        forLanguageID languageID: String,
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels
    ) -> [VoiceEngineLanguageRoute] {
        guard let language = Self.language(id: languageID, availableModels: availableModels) else {
            return []
        }
        return Self.routes(for: language, availableModels: availableModels)
    }

    /// Number of dictation languages the catalog can route to the given model,
    /// independent of which models are currently enabled. Cached because the
    /// engine cards read this on every render.
    static func supportedLanguageCount(for model: SettingsStore.SpeechModel) -> Int {
        if let cached = self.supportedLanguageCountsByModel[model] {
            return cached
        }
        let count = self.languageDefinitions.filter { language in
            self.routeCandidates(for: language).contains { $0.model == model }
        }.count
        self.supportedLanguageCountsByModel[model] = count
        return count
    }

    private static var supportedLanguageCountsByModel: [SettingsStore.SpeechModel: Int] = [:]

    static func apply(_ route: VoiceEngineLanguageRoute, to settings: SettingsStore = .shared) {
        settings.onboardingSelectedLanguageID = route.language.id
        settings.selectedSpeechModel = route.model

        switch route.binding {
        case .automatic:
            break
        case let .appleSpeech(localeIdentifier):
            settings.selectedAppleSpeechLocaleIdentifier = localeIdentifier
        }
    }

    private static func routeCandidates(for language: VoiceEngineLanguage) -> [VoiceEngineLanguageRoute] {
        var routes: [VoiceEngineLanguageRoute] = []

        if language.id == "en" {
            routes.append(Self.route(language, .parakeetTDTv2, .automatic))
        }

        if let appleSpeechAnalyzerLocale = Self.appleSpeechAnalyzerLocaleIdentifier(for: language.id) {
            routes.append(Self.route(language, .appleSpeechAnalyzer, .appleSpeech(localeIdentifier: appleSpeechAnalyzerLocale)))
        }

        return routes
    }

    private static func route(
        _ language: VoiceEngineLanguage,
        _ model: SettingsStore.SpeechModel,
        _ binding: VoiceEngineLanguageRoute.LanguageBinding
    ) -> VoiceEngineLanguageRoute {
        VoiceEngineLanguageRoute(language: language, model: model, binding: binding)
    }

    private static func appleSpeechAnalyzerLocaleIdentifier(for languageID: String) -> String? {
        self.appleSpeechAnalyzerLocaleMap[languageID]
    }

    private static let popularLanguageIDs: Set<String> = [
        "en",
        "es",
        "fr",
        "de",
        "pt",
        "it",
        "ja",
        "ko",
        "zh",
        "hi",
        "ar",
    ]

    private static let appleSpeechAnalyzerLocaleMap: [String: String] = [
        "de": "de-DE",
        "en": "en-US",
        "es": "es-US",
        "fr": "fr-FR",
        "it": "it-IT",
        "ja": "ja-JP",
        "ko": "ko-KR",
        "pt": "pt-BR",
        "zh": "zh-CN",
    ]

    private static let languageDefinitions: [VoiceEngineLanguage] = [
        Self.language("af", "Afrikaans"),
        Self.language("am", "Amharic"),
        Self.language("ar", "Arabic", aliases: ["Arab"]),
        Self.language("as", "Assamese"),
        Self.language("az", "Azerbaijani"),
        Self.language("ba", "Bashkir"),
        Self.language("be", "Belarusian"),
        Self.language("bg", "Bulgarian"),
        Self.language("bn", "Bengali", aliases: ["Bangla"]),
        Self.language("bo", "Tibetan"),
        Self.language("br", "Breton"),
        Self.language("bs", "Bosnian"),
        Self.language("ca", "Catalan"),
        Self.language("cs", "Czech"),
        Self.language("cy", "Welsh"),
        Self.language("da", "Danish"),
        Self.language("de", "German", aliases: ["Deutsch"]),
        Self.language("el", "Greek"),
        Self.language("en", "English"),
        Self.language("es", "Spanish", aliases: ["Castilian"]),
        Self.language("et", "Estonian"),
        Self.language("eu", "Basque"),
        Self.language("fa", "Persian", aliases: ["Farsi"]),
        Self.language("fi", "Finnish"),
        Self.language("fo", "Faroese"),
        Self.language("fr", "French"),
        Self.language("gl", "Galician"),
        Self.language("gu", "Gujarati"),
        Self.language("ha", "Hausa"),
        Self.language("haw", "Hawaiian"),
        Self.language("he", "Hebrew"),
        Self.language("hi", "Hindi"),
        Self.language("hr", "Croatian"),
        Self.language("ht", "Haitian Creole"),
        Self.language("hu", "Hungarian"),
        Self.language("hy", "Armenian"),
        Self.language("id", "Indonesian"),
        Self.language("is", "Icelandic"),
        Self.language("it", "Italian"),
        Self.language("ja", "Japanese"),
        Self.language("jw", "Javanese"),
        Self.language("ka", "Georgian"),
        Self.language("kk", "Kazakh"),
        Self.language("km", "Khmer"),
        Self.language("kn", "Kannada"),
        Self.language("ko", "Korean"),
        Self.language("la", "Latin"),
        Self.language("lb", "Luxembourgish"),
        Self.language("ln", "Lingala"),
        Self.language("lo", "Lao"),
        Self.language("lt", "Lithuanian"),
        Self.language("lv", "Latvian"),
        Self.language("mg", "Malagasy"),
        Self.language("mi", "Maori"),
        Self.language("mk", "Macedonian"),
        Self.language("ml", "Malayalam"),
        Self.language("mn", "Mongolian"),
        Self.language("mr", "Marathi"),
        Self.language("ms", "Malay"),
        Self.language("mt", "Maltese"),
        Self.language("my", "Myanmar", aliases: ["Burmese"]),
        Self.language("ne", "Nepali"),
        Self.language("nl", "Dutch"),
        Self.language("nn", "Norwegian Nynorsk"),
        Self.language("no", "Norwegian", aliases: ["Norwegian Bokmal"]),
        Self.language("oc", "Occitan"),
        Self.language("pa", "Punjabi"),
        Self.language("pl", "Polish"),
        Self.language("ps", "Pashto"),
        Self.language("pt", "Portuguese"),
        Self.language("ro", "Romanian", aliases: ["Moldavian", "Moldovan"]),
        Self.language("ru", "Russian"),
        Self.language("sa", "Sanskrit"),
        Self.language("sd", "Sindhi"),
        Self.language("si", "Sinhala", aliases: ["Sinhalese"]),
        Self.language("sk", "Slovak"),
        Self.language("sl", "Slovenian"),
        Self.language("sn", "Shona"),
        Self.language("so", "Somali"),
        Self.language("sq", "Albanian"),
        Self.language("sr", "Serbian"),
        Self.language("su", "Sundanese"),
        Self.language("sv", "Swedish"),
        Self.language("sw", "Swahili"),
        Self.language("ta", "Tamil"),
        Self.language("te", "Telugu"),
        Self.language("tg", "Tajik"),
        Self.language("th", "Thai"),
        Self.language("tk", "Turkmen"),
        Self.language("tl", "Tagalog", aliases: ["Filipino"]),
        Self.language("tr", "Turkish"),
        Self.language("tt", "Tatar"),
        Self.language("uk", "Ukrainian"),
        Self.language("ur", "Urdu"),
        Self.language("uz", "Uzbek"),
        Self.language("vi", "Vietnamese"),
        Self.language("yi", "Yiddish"),
        Self.language("yo", "Yoruba"),
        Self.language("zh", "Mandarin Chinese", aliases: ["Chinese", "Mandarin"]),
    ]

    private static func language(
        _ id: String,
        _ displayName: String,
        aliases: [String] = []
    ) -> VoiceEngineLanguage {
        VoiceEngineLanguage(
            id: id,
            displayName: displayName,
            aliases: aliases,
            isPopular: self.popularLanguageIDs.contains(id)
        )
    }
}
