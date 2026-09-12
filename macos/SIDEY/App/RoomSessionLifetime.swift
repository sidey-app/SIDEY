import Foundation

@MainActor
final class RoomSessionLifetime {
    var switchPipeline: RoomSwitchPipeline!
    var bootstrapTask: Task<Void, Never>?
    var eventTask: Task<Void, Never>?
    var typingTask: Task<Void, Never>?
    var bubbleExpiryTask: Task<Void, Never>?
    var typingLease = TypingLease()
    var pulseCooldown = CharacterPulseCooldown()
    var throwCooldown = CharacterThrowCooldown()

    func cancel() {
        bootstrapTask?.cancel()
        eventTask?.cancel()
        typingTask?.cancel()
        bubbleExpiryTask?.cancel()
        bootstrapTask = nil
        // The stream consumer clears eventTask only after cancellation has drained.
        typingTask = nil
        bubbleExpiryTask = nil
        switchPipeline?.cancel()
        typingLease = TypingLease()
        pulseCooldown = CharacterPulseCooldown()
        throwCooldown = CharacterThrowCooldown()
    }
}
