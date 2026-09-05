import Foundation

/// Curated, local vocabulary packs that users can opt into for Parakeet recognition.
/// Presets are deliberately compact so enabling every pack still leaves room for
/// user-managed words inside FluidAudio's 256-term vocabulary limit.
struct VocabularyPreset: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let systemImage: String
    let terms: [ParakeetVocabularyStore.VocabularyConfig.Term]
}

enum VocabularyPresetCatalog {
    typealias Term = ParakeetVocabularyStore.VocabularyConfig.Term

    static let all: [VocabularyPreset] = [
        VocabularyPreset(
            id: "artificial-intelligence",
            title: "AI & Data",
            description: "Models, prompts, training, and modern AI tools",
            systemImage: "brain.head.profile",
            terms: VocabularyPresetCatalog.makeTerms([
                "AI",
                "artificial intelligence",
                "machine learning",
                "large language model",
                "LLM",
                "generative AI",
                "neural network",
                "transformer",
                "inference",
                "fine-tuning",
                "tokenization",
                "embedding",
                "vector database",
                "retrieval-augmented generation",
                "RAG",
                "prompt engineering",
                "multimodal",
                "hallucination",
                "ChatGPT",
                "OpenAI",
            ])
        ),
        VocabularyPreset(
            id: "law",
            title: "Law",
            description: "Litigation, procedure, and legal practice",
            systemImage: "scale.3d",
            terms: VocabularyPresetCatalog.makeTerms([
                "affidavit",
                "amicus curiae",
                "appellant",
                "appellee",
                "arbitration",
                "deposition",
                "discovery",
                "due diligence",
                "fiduciary",
                "habeas corpus",
                "injunction",
                "jurisdiction",
                "litigation",
                "memorandum",
                "plaintiff",
                "precedent",
                "subpoena",
                "voir dire",
            ])
        ),
        VocabularyPreset(
            id: "accounting",
            title: "Accounting",
            description: "Financial statements, close, audit, and tax",
            systemImage: "sum",
            terms: VocabularyPresetCatalog.makeTerms([
                "accounts payable",
                "accounts receivable",
                "accrual",
                "amortization",
                "balance sheet",
                "cash flow statement",
                "chart of accounts",
                "CPA",
                "deferred revenue",
                "depreciation",
                "double-entry accounting",
                "GAAP",
                "general ledger",
                "journal entry",
                "materiality",
                "reconciliation",
                "retained earnings",
                "trial balance",
            ])
        ),
        VocabularyPreset(
            id: "finance",
            title: "Finance",
            description: "Corporate finance, valuation, and reporting",
            systemImage: "chart.line.uptrend.xyaxis",
            terms: VocabularyPresetCatalog.makeTerms([
                "basis point",
                "bond yield",
                "capital expenditure",
                "cash flow",
                "credit spread",
                "debt-to-equity ratio",
                "discounted cash flow",
                "EBITDA",
                "enterprise value",
                "fiscal year",
                "free cash flow",
                "gross margin",
                "interest rate",
                "liquidity",
                "net present value",
                "operating margin",
                "return on equity",
                "working capital",
            ])
        ),
        VocabularyPreset(
            id: "investment",
            title: "Investment",
            description: "Markets, portfolios, funds, and deal terms",
            systemImage: "briefcase.fill",
            terms: VocabularyPresetCatalog.makeTerms([
                "alpha",
                "asset allocation",
                "benchmark",
                "beta",
                "capital gain",
                "diversification",
                "dividend yield",
                "dollar-cost averaging",
                "ETF",
                "exchange-traded fund",
                "hedge fund",
                "index fund",
                "internal rate of return",
                "private equity",
                "risk-adjusted return",
                "Sharpe ratio",
                "venture capital",
                "yield curve",
            ])
        ),
        VocabularyPreset(
            id: "art",
            title: "Art & Design",
            description: "Studio practice, criticism, and visual design",
            systemImage: "paintpalette.fill",
            terms: VocabularyPresetCatalog.makeTerms([
                "avant-garde",
                "chiaroscuro",
                "composition",
                "conceptual art",
                "contemporary art",
                "curatorial",
                "diptych",
                "installation art",
                "mixed media",
                "negative space",
                "palette",
                "perspective",
                "plein air",
                "provenance",
                "sculpture",
                "triptych",
                "trompe-l'oeil",
                "typography",
            ])
        ),
        VocabularyPreset(
            id: "politics",
            title: "Politics",
            description: "Government, elections, legislation, and policy",
            systemImage: "building.columns.fill",
            terms: VocabularyPresetCatalog.makeTerms([
                "bipartisan",
                "caucus",
                "constituency",
                "filibuster",
                "gerrymandering",
                "incumbent",
                "legislation",
                "legislature",
                "lobbying",
                "parliamentary",
                "plurality",
                "polling",
                "primary election",
                "public policy",
                "referendum",
                "separation of powers",
                "super PAC",
                "voter turnout",
            ])
        ),
        VocabularyPreset(
            id: "journalism",
            title: "Journalism",
            description: "Reporting, editing, publishing, and newsrooms",
            systemImage: "newspaper.fill",
            terms: VocabularyPresetCatalog.makeTerms([
                "attribution",
                "byline",
                "copy editor",
                "dateline",
                "editorial",
                "embargo",
                "fact-checking",
                "feature story",
                "headline",
                "investigative journalism",
                "lede",
                "masthead",
                "news desk",
                "off the record",
                "op-ed",
                "press release",
                "style guide",
                "wire service",
            ])
        ),
        VocabularyPreset(
            id: "software",
            title: "Software",
            description: "Engineering, code review, systems, and delivery",
            systemImage: "chevron.left.forwardslash.chevron.right",
            terms: VocabularyPresetCatalog.makeTerms([
                "API",
                "backend",
                "CI/CD",
                "codebase",
                "continuous integration",
                "database migration",
                "dependency",
                "deployment",
                "frontend",
                "GitHub",
                "latency",
                "microservice",
                "pull request",
                "repository",
                "runtime",
                "SDK",
                "source control",
                "unit test",
            ])
        ),
        VocabularyPreset(
            id: "cybersecurity",
            title: "Cybersecurity",
            description: "Identity, threats, defense, and security testing",
            systemImage: "lock.shield.fill",
            terms: VocabularyPresetCatalog.makeTerms([
                "authentication",
                "authorization",
                "ciphertext",
                "credential stuffing",
                "cryptography",
                "CVE",
                "cybersecurity",
                "DDoS",
                "endpoint detection and response",
                "encryption",
                "firewall",
                "malware",
                "multi-factor authentication",
                "penetration testing",
                "phishing",
                "ransomware",
                "threat actor",
                "zero trust",
            ])
        ),
    ]

    static let allIDs = Set(VocabularyPresetCatalog.all.map(\.id))

    static func normalizedIDs<S: Sequence>(_ ids: S) -> Set<String> where S.Element == String {
        Set(ids).intersection(self.allIDs)
    }

    static func presets(for ids: Set<String>) -> [VocabularyPreset] {
        let normalized = self.normalizedIDs(ids)
        return self.all.filter { normalized.contains($0.id) }
    }

    static func terms(for ids: Set<String>) -> [Term] {
        self.presets(for: ids).flatMap(\.terms)
    }

    private static func makeTerms(_ values: [String]) -> [Term] {
        values.map { Term(text: $0, weight: 5.5) }
    }
}
