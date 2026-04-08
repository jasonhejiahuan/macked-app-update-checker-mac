import SwiftData

enum PersistenceController {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema([
            TrackedApp.self,
            AppSettings.self,
        ])

        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
