import Foundation
import SwiftData

/// Owns the one `ModelContainer` of the app. The window group and `Reminders` both use it, so a
/// notification action that launches the app in the background reads the same store the screens do.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let container: ModelContainer

    private init() {
        do {
            container = try ModelContainer(for: RunRecord.self, WorkoutRecord.self)
        } catch {
            fatalError("MilePace could not open its data store: \(error)")
        }
    }

    /// Every saved run and workout, read with a fresh `ModelContext`. Unsaved changes in the main
    /// context are saved first so a run that was just inserted is not missed.
    func loadActivity() -> (runs: [LoggedRun], workouts: [LoggedWorkout]) {
        if container.mainContext.hasChanges {
            try? container.mainContext.save()
        }
        let context = ModelContext(container)
        let runRecords = (try? context.fetch(FetchDescriptor<RunRecord>())) ?? []
        let workoutRecords = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        let runs = runRecords.map { LoggedRun(record: $0) }
        let workouts = workoutRecords.map { LoggedWorkout(record: $0) }
        return (runs: runs, workouts: workouts)
    }

    /// Deletes every run and workout made during a test week and saves. False when the save failed;
    /// the deletions are then rolled back, so nothing is half done.
    func deleteTestRecords() -> Bool {
        let context = container.mainContext
        do {
            let runs = try context.fetch(FetchDescriptor<RunRecord>())
            for run in runs where run.isTest {
                context.delete(run)
            }
            let workouts = try context.fetch(FetchDescriptor<WorkoutRecord>())
            for workout in workouts where workout.isTest {
                context.delete(workout)
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }
}

extension LoggedRun {
    init(record: RunRecord) {
        self.init(date: record.date, meters: record.distanceMeters, workoutName: record.workoutName, isTest: record.isTest)
    }
}

extension LoggedWorkout {
    /// Rep meters are the reps that were run (finished early counts only what was done).
    init(record: WorkoutRecord) {
        let reps = Double(record.repTimes.count)
        let distance = Double(record.spec?.repDistance ?? 0)
        self.init(date: record.date, name: record.name, repMeters: reps * distance, isTest: record.isTest)
    }
}
