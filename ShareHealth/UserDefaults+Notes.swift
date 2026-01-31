import Foundation

extension UserDefaults {
    private static let notesKey = "storedStepNotes"
    
    func saveNotes(_ notes: String, forDate date: String) {
        var storedNotes = dictionary(forKey: Self.notesKey) as? [String: String] ?? [:]
        storedNotes[date] = notes
        set(storedNotes, forKey: Self.notesKey)
    }
    
    func getNotes(forDate date: String) -> String? {
        let storedNotes = dictionary(forKey: Self.notesKey) as? [String: String]
        return storedNotes?[date]
    }
}
