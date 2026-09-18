import Foundation
import OSLog

@MainActor
struct GlobalShortcutCommands {
    var isComposerVisible: () -> Bool
    var openComposer: () -> Void
    var dismissComposer: () -> Void
    var openMainWindow: () -> Void
    var openGroupSettings: () -> Void
    var groupsLoaded: () -> Bool
    var toggleOverlay: () -> Void
    var toggleQuietMode: () -> Void
    var showNotice: (GlobalShortcutNotice) -> Void
}

/// Keeps the user-assigned global shortcuts registered, reports their state to settings and
/// routes presses to the same paths as the status menu.
@MainActor
final class GlobalShortcutController {
    private struct RegisteredShortcut {
        let shortcut: GlobalShortcut
        let registration: GlobalHotKeyRegistration
    }

    private let model: AppModel
    private let registrar: any GlobalHotKeyRegistering
    private let commands: GlobalShortcutCommands
    private let onPreferencesChanged: () -> Void
    private var registrations: [GlobalShortcutAction: RegisteredShortcut] = [:]
    // Log only the action name and OSStatus. Key input is never logged.
    private let logger = Logger(subsystem: "app.sidey.desktop", category: "GlobalShortcuts")

    init(
        model: AppModel,
        registrar: any GlobalHotKeyRegistering,
        commands: GlobalShortcutCommands,
        onPreferencesChanged: @escaping () -> Void
    ) {
        self.model = model
        self.registrar = registrar
        self.commands = commands
        self.onPreferencesChanged = onPreferencesChanged
    }

    func start() {
        registerAssignedShortcuts()
    }

    func beginRecording(_ action: GlobalShortcutAction) {
        model.recordingGlobalShortcutAction = action
        // Pause SIDEY's own shortcuts so the pressed combination reaches the recorder.
        unregisterAll()
    }

    func cancelRecording(_ action: GlobalShortcutAction? = nil) {
        guard let recordingAction = model.recordingGlobalShortcutAction,
              action == nil || action == recordingAction
        else { return }
        model.recordingGlobalShortcutAction = nil
        registerAssignedShortcuts()
    }

    func record(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) {
        guard model.recordingGlobalShortcutAction == action else { return }
        model.recordingGlobalShortcutAction = nil
        unregisterAll()
        if let rejection = shortcut.rejection(for: action, among: model.preferences.globalShortcuts) {
            registerAssignedShortcuts()
            model.globalShortcutStatuses[action] = .rejected(rejection)
            return
        }
        // SIDEY's own shortcuts are still paused, so a failure means another app owns the combination.
        switch registrar.register(shortcut, onPress: pressHandler(for: action)) {
        case .success(let registration):
            registrations[action] = RegisteredShortcut(shortcut: shortcut, registration: registration)
            if model.preferences.globalShortcuts[action] != shortcut {
                model.preferences.globalShortcuts[action] = shortcut
                onPreferencesChanged()
            }
            registerAssignedShortcuts()
        case .failure(let error):
            logRegistrationFailure(action: action, status: error.status)
            registerAssignedShortcuts()
            model.globalShortcutStatuses[action] = .rejected(.unavailable)
        }
    }

    func clear(_ action: GlobalShortcutAction) {
        model.recordingGlobalShortcutAction = nil
        let hadShortcut = model.preferences.globalShortcuts[action] != nil
        model.preferences.globalShortcuts[action] = nil
        registerAssignedShortcuts()
        if hadShortcut {
            onPreferencesChanged()
        }
    }

    private func registerAssignedShortcuts() {
        var statuses: [GlobalShortcutAction: GlobalShortcutStatus] = [:]
        for action in GlobalShortcutAction.allCases {
            let assigned = model.preferences.globalShortcuts[action]
            if let current = registrations[action], current.shortcut != assigned {
                registrar.unregister(current.registration)
                registrations[action] = nil
            }
            guard let shortcut = assigned else { continue }
            if registrations[action] != nil {
                statuses[action] = .active
                continue
            }
            switch registrar.register(shortcut, onPress: pressHandler(for: action)) {
            case .success(let registration):
                registrations[action] = RegisteredShortcut(shortcut: shortcut, registration: registration)
                statuses[action] = .active
            case .failure(let error):
                // Keep the saved combination; it is retried on the next launch or settings change.
                logRegistrationFailure(action: action, status: error.status)
                statuses[action] = .unavailable
            }
        }
        if model.globalShortcutStatuses != statuses {
            model.globalShortcutStatuses = statuses
        }
    }

    private func unregisterAll() {
        for registered in registrations.values {
            registrar.unregister(registered.registration)
        }
        registrations.removeAll()
    }

    private func pressHandler(for action: GlobalShortcutAction) -> () -> Void {
        return { [weak self] in self?.handlePress(action) }
    }

    private func handlePress(_ action: GlobalShortcutAction) {
        // A shortcut is pressed without seeing the menu, so every press shows a result.
        // Before onboarding the main window shows what to do next.
        guard model.preferences.onboardingComplete else {
            commands.openMainWindow()
            return
        }
        switch action {
        case .toggleComposer:
            toggleComposer()
        case .toggleOverlay:
            commands.toggleOverlay()
        case .toggleQuietMode:
            commands.toggleQuietMode()
            // Quiet mode changes nothing on screen until a message arrives, so confirm it.
            commands.showNotice(model.preferences.quietModeEnabled ? .quietModeOn : .quietModeOff)
        }
    }

    private func toggleComposer() {
        if commands.isComposerVisible() {
            commands.dismissComposer()
            return
        }
        guard model.activeRoom != nil else {
            // The composer belongs to the user's character in an active group, so point to
            // group settings instead. Until groups load, do not claim that there are none.
            commands.openGroupSettings()
            commands.showNotice(commands.groupsLoaded() ? .groupRequired : .waitingForGroups)
            return
        }
        commands.openComposer()
        if commands.isComposerVisible() { return }
        // The overlay cannot appear yet, for example while the session is restoring.
        commands.openMainWindow()
    }

    private func logRegistrationFailure(action: GlobalShortcutAction, status: OSStatus) {
        logger.error(
            "registration failed action=\(action.rawValue, privacy: .public) status=\(status, privacy: .public)"
        )
    }
}
