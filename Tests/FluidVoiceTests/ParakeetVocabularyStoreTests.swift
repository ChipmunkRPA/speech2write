@testable import FluidVoice
import XCTest

@MainActor
final class ParakeetVocabularyStoreTests: XCTestCase {
    func testLegacyBrandTermIsReplacedWithoutChangingUserTerms() {
        let config = self.config(
            terms: [
                .init(
                    text: "Platypus Flow",
                    weight: 9.0,
                    aliases: ["platypus", "platy pus flow"]
                ),
                .init(text: "Acme Legal", weight: 7.0, aliases: ["acme"]),
            ]
        )

        let migration = ParakeetVocabularyStore.migratingLegacyBrandTerm(in: config)

        XCTAssertTrue(migration.didChange)
        XCTAssertEqual(migration.config.terms.map(\.text), ["Speech2Write", "Acme Legal"])
        XCTAssertEqual(migration.config.terms[0].weight, 10.0)
        XCTAssertEqual(
            Set(migration.config.terms[0].aliases),
            Set(["speech2write", "speech to write", "speech two write"])
        )
        XCTAssertEqual(migration.config.terms[1], config.terms[1])
    }

    func testExistingCurrentBrandTermIsMergedWithoutDuplication() {
        let config = self.config(
            terms: [
                .init(text: "Platypus Flow", weight: 12.0, aliases: ["platypus"]),
                .init(text: "speech2write", weight: 8.0, aliases: ["custom pronunciation", "platy pus flow"]),
            ]
        )

        let migration = ParakeetVocabularyStore.migratingLegacyBrandTerm(in: config)

        XCTAssertTrue(migration.didChange)
        XCTAssertEqual(migration.config.terms.count, 1)
        XCTAssertEqual(migration.config.terms[0].text, "Speech2Write")
        XCTAssertEqual(migration.config.terms[0].weight, 12.0)
        XCTAssertTrue(migration.config.terms[0].aliases.contains("custom pronunciation"))
        XCTAssertFalse(migration.config.terms[0].aliases.contains("platypus"))
        XCTAssertFalse(migration.config.terms[0].aliases.contains("platy pus flow"))
    }

    func testVocabularyWithoutLegacyBrandTermIsUnchanged() {
        let config = self.config(terms: [.init(text: "Ray Sang", weight: 10.0, aliases: ["ray"])])

        let migration = ParakeetVocabularyStore.migratingLegacyBrandTerm(in: config)

        XCTAssertFalse(migration.didChange)
        XCTAssertEqual(migration.config.terms, config.terms)
    }

    func testRequiredBrandTermsAreAddedWithoutRemovingUserTerms() {
        let config = self.config(terms: [.init(text: "Ray Sang", weight: 8.0)])

        let migration = ParakeetVocabularyStore.addingRequiredBrandTerms(in: config)
        let texts = Set(migration.config.terms.map(\.text))

        XCTAssertTrue(migration.didChange)
        XCTAssertTrue(texts.contains("Ray Sang"))
        XCTAssertTrue(texts.contains("Speech2Write"))
        XCTAssertTrue(texts.contains("CPA Automation"))
        XCTAssertTrue(texts.contains("cpaautomation.ai"))
    }

    func testPresetCatalogHasEverySupportedFieldAndUniqueIDs() {
        let expectedIDs: Set = [
            "accounting",
            "art",
            "artificial-intelligence",
            "cybersecurity",
            "finance",
            "investment",
            "journalism",
            "law",
            "politics",
            "software",
        ]

        XCTAssertEqual(VocabularyPresetCatalog.allIDs, expectedIDs)
        XCTAssertEqual(VocabularyPresetCatalog.all.count, expectedIDs.count)
        XCTAssertTrue(VocabularyPresetCatalog.all.allSatisfy { !$0.terms.isEmpty })

        let allTermCount = VocabularyPresetCatalog.terms(for: expectedIDs).count
        XCTAssertLessThanOrEqual(allTermCount, 200)
    }

    func testPresetSelectionIgnoresUnknownIDs() {
        let selected = VocabularyPresetCatalog.normalizedIDs(["law", "not-a-real-preset"])

        XCTAssertEqual(selected, Set(["law"]))
        XCTAssertEqual(VocabularyPresetCatalog.presets(for: selected).map(\.id), ["law"])
    }

    func testPresetTermsMergeWithCustomWordsAndDictionaryOverrides() {
        let presetTerms = [
            ParakeetVocabularyStore.VocabularyConfig.Term(
                text: "reconciliation",
                weight: 5.5,
                aliases: ["reconcile"]
            ),
        ]
        let userTerms = [
            ParakeetVocabularyStore.VocabularyConfig.Term(
                text: "Reconciliation",
                weight: 7.0,
                aliases: ["recon"]
            ),
        ]
        let dictionaryEntries = [
            SettingsStore.CustomDictionaryEntry(
                triggers: ["rec conciliation"],
                replacement: "Reconciliation"
            ),
        ]

        let merged = ParakeetVocabularyStore.mergeAndNormalizeTerms(
            jsonTerms: userTerms,
            dictionaryEntries: dictionaryEntries,
            presetTerms: presetTerms
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Reconciliation")
        XCTAssertEqual(merged[0].weight, 8.0)
        XCTAssertEqual(Set(merged[0].aliases), Set(["recon", "reconcile", "rec conciliation"]))
    }

    private func config(
        terms: [ParakeetVocabularyStore.VocabularyConfig.Term]
    ) -> ParakeetVocabularyStore.VocabularyConfig {
        ParakeetVocabularyStore.VocabularyConfig(
            alpha: 2.8,
            minCtcScore: -2.2,
            minSimilarity: 0.72,
            minCombinedConfidence: 0.64,
            minTermLength: 3,
            terms: terms
        )
    }
}
