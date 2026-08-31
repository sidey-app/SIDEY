import Foundation

struct InviteCopyFeedbackState: Equatable {
    static let confirmationDuration: Duration = .seconds(3)

    private(set) var showsConfirmation = false
    private(set) var generation = 0

    mutating func recordResult(_ succeeded: Bool) -> Int? {
        guard succeeded else { return nil }
        generation += 1
        showsConfirmation = true
        return generation
    }

    mutating func clear(generation expectedGeneration: Int) {
        guard generation == expectedGeneration else { return }
        showsConfirmation = false
    }

    mutating func cancel() {
        generation += 1
        showsConfirmation = false
    }
}
