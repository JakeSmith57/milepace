import XCTest
@testable import MilePace

final class VoiceCatalogTests: XCTestCase {
    private func voice(_ id: String, _ name: String, _ language: String, _ quality: Int = 1) -> VoiceOption {
        return VoiceOption(id: id, name: name, language: language, quality: quality)
    }

    func testFiltersNonEnglishAndNovelty() {
        let all = [
            voice("com.apple.voice.compact.en-US.Samantha", "Samantha", "en-US"),
            voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", "fr-FR"),
            voice("com.apple.voice.compact.es-ES.Monica", "Monica", "es-ES"),
            voice("com.apple.speech.synthesis.voice.Bells", "Bells", "en-US"),
            voice("com.apple.speech.synthesis.voice.Zarvox", "Zarvox", "en-US"),
            voice("com.apple.eloquence.en-US.Flo", "Flo", "en-US")
        ]
        let result = VoiceCatalog.options(from: all)
        XCTAssertEqual(result.map { $0.name }, ["Samantha"])
    }

    func testOrdersByQualityThenUSFirstThenName() {
        let all = [
            voice("a", "Zoe", "en-GB", 1),
            voice("b", "Daniel", "en-GB", 1),
            voice("c", "Samantha", "en-US", 1),
            voice("d", "Ava", "en-US", 3),
            voice("e", "Tessa", "en-ZA", 2),
            voice("f", "Alex", "en-US", 2),
            voice("g", "Aaron", "en-US", 1)
        ]
        let result = VoiceCatalog.options(from: all)
        XCTAssertEqual(result.map { $0.name }, ["Ava", "Alex", "Tessa", "Aaron", "Samantha", "Daniel", "Zoe"])
    }

    func testEnUSBeforeEnGBAtEqualQuality() {
        let all = [voice("gb", "Arthur", "en-GB", 2), voice("us", "Zed", "en-US", 2)]
        XCTAssertEqual(VoiceCatalog.options(from: all).map { $0.id }, ["us", "gb"])
    }

    func testDeduplicatesByIdentifier() {
        let all = [voice("same", "Ava", "en-US", 3), voice("same", "Ava", "en-US", 3), voice("other", "Nora", "en-US")]
        XCTAssertEqual(VoiceCatalog.options(from: all).map { $0.id }, ["same", "other"])
    }

    func testLabelText() {
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Ava", "en-US", 3)), "ava  premium  us")
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Daniel", "en-GB", 2)), "daniel  enhanced  uk")
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Karen", "en-AU", 1)), "karen  au")
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Moira", "en-IE", 1)), "moira  ie")
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Tessa", "en-ZA", 1)), "tessa  za")
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Rishi", "en-IN", 1)), "rishi  in")
        XCTAssertEqual(VoiceCatalog.label(voice("x", "Other", "en-NZ", 1)), "other  nz")
    }

    func testResolve() {
        let available = [voice("a", "Ava", "en-US", 3), voice("b", "Nora", "en-US")]
        XCTAssertEqual(VoiceCatalog.resolve(identifier: "b", available: available)?.name, "Nora")
        XCTAssertNil(VoiceCatalog.resolve(identifier: "missing", available: available))
        XCTAssertNil(VoiceCatalog.resolve(identifier: "", available: available))
    }
}
