import Foundation

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    let preferences: AppPreferences
    let repository: SQLiteNoteRepository
    let model: AppModel
    let dictation: DictationCoordinator
    let deckCoordinator: DeckCoordinator
    let libraryWindow: LibraryWindowController
    let undoToast: UndoToastController

    private init() {
        preferences = .shared
        do { repository = try SQLiteNoteRepository() }
        catch { fatalError("Unable to create notes repository: \(error.localizedDescription)") }
        model = AppModel(repository: repository)
        dictation = DictationCoordinator(preferences: preferences)
        deckCoordinator = DeckCoordinator(model: model, preferences: preferences, dictation: dictation)
        libraryWindow = LibraryWindowController(model: model)
        undoToast = UndoToastController(model: model)
    }
}
