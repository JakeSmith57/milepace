import XCTest
@testable import MilePace

/// The routine library (v1.11): the shipped `routines.json` and the session-to-routine mapping.
final class RoutinesTests: XCTestCase {
    private func bundled() throws -> RoutineLibrary {
        let library = RoutineLoader.load(bundle: Bundle(for: PlanStore.self))
        return try XCTUnwrap(library, "routines.json is missing from the app bundle or does not parse")
    }

    private func exercise(video: String?) -> RoutineExercise {
        return RoutineExercise(name: "n", dose: "d", how: "h", video: video)
    }

    func testTheShippedFileDecodesWithRoutinesInEveryGroup() throws {
        let library = try bundled()
        XCTAssertFalse(library.routines.isEmpty)
        for group in RoutineGroup.allCases {
            XCTAssertFalse(library.routines(in: group).isEmpty, "no routine in \(group.rawValue)")
        }
    }

    func testEveryRoutineHasExercisesAndUniqueNames() throws {
        for routine in try bundled().routines {
            XCTAssertFalse(routine.exercises.isEmpty, routine.id)
            let names = routine.exercises.map { $0.name }
            XCTAssertEqual(Set(names).count, names.count, "duplicate exercise name in \(routine.id)")
        }
    }

    func testRoutineIdsAreUnique() throws {
        let ids = try bundled().routines.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEverySuggestedRoutineExists() throws {
        let library = try bundled()
        let kinds: [SessionKind] = [.easy, .long, .road, .track, .timeTrial, .race, .other]
        for kind in kinds {
            let ids = RoutineSuggestion.ids(for: kind)
            XCTAssertNotNil(library.routine(id: ids.before), "\(kind) before")
            if let after = ids.after {
                XCTAssertNotNil(library.routine(id: after), "\(kind) after")
            }
        }
    }

    func testEasyRunsGetOnlyAWarmUpAndWorkoutsGetBoth() {
        XCTAssertNil(RoutineSuggestion.ids(for: .easy).after)
        XCTAssertNil(RoutineSuggestion.ids(for: .long).after)
        XCTAssertEqual(RoutineSuggestion.ids(for: .track).after, "cooldown")
        XCTAssertEqual(RoutineSuggestion.ids(for: .timeTrial).before, "warmup-workout")
    }

    func testSearchLinksAreToldApartFromSingleVideos() {
        XCTAssertTrue(exercise(video: "https://www.youtube.com/results?search_query=calf+raise").isSearchLink)
        XCTAssertFalse(exercise(video: "https://www.youtube.com/watch?v=korxBhGzzJE").isSearchLink)
        XCTAssertFalse(exercise(video: nil).isSearchLink)
        XCTAssertNil(exercise(video: nil).videoURL)
    }

    func testEveryVideoLinkIsAYouTubeURL() throws {
        for routine in try bundled().routines {
            for item in routine.exercises {
                guard let video = item.video else { continue }
                let url = try XCTUnwrap(URL(string: video), "\(routine.id): \(item.name)")
                XCTAssertTrue(url.host?.contains("youtube.com") ?? false, "\(routine.id): \(item.name)")
            }
        }
    }

    func testDecodeReturnsNilForGarbage() {
        XCTAssertNil(RoutineLoader.decode(Data("nope".utf8)))
    }
}
