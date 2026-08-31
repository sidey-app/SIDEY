import AppKit
import Observation
import QuartzCore

@MainActor
final class AppCoordinator {
    let model: AppModel

    private let preferencesStore: PreferencesStore
    private let legacyMigrator: LegacySettingsMigrator
    private let backend: SideyBackend?
    private let configurationError: Error?
    private let launchReason: LaunchReason
    private let onLandingFirstFrame: () -> Void
    private let launchAtLoginController = LaunchAtLoginController()
    private lazy var overlayWindows = OverlayWindowGroup(
        model: model,
        onSend: { [weak self] body in self?.sendMessage(body) },
        onTypingChanged: { [weak self] active in self?.typingChanged(active) },
        onRegionChanged: { [weak self] in self?.persistPreferences() }
    )
    private lazy var historyWindow = HistoryWindowController(model: model)
    private lazy var settingsWindow = SettingsWindowController(
        model: model,
        actions: SettingsActions(
            onOverlayVisibilityChanged: { [weak self] visible in self?.setOverlayVisible(visible) },
            onOverlayRegionChanged: { [weak self] preference in self?.setOverlayRegion(preference) },
            onShowOfflineMembersChanged: { [weak self] visible in self?.setShowOfflineMembers(visible) },
            onQuietModeChanged: { [weak self] enabled in self?.setQuietMode(enabled) },
            onLaunchAtLoginChanged: { [weak self] enabled in self?.setLaunchAtLogin(enabled) },
            onSaveProfile: { [weak self] in self?.saveProfile() },
            onCreateRoom: { [weak self] in self?.createRoom() },
            onJoinRoom: { [weak self] in self?.joinRoom() },
            onSelectRoom: { [weak self] roomID in self?.selectRoom(roomID) },
            onCopyInviteCode: { [weak self] roomID in self?.copyInviteCode(roomID: roomID) }
        ),
        onClose: { [weak self] in self?.settingsDidClose() }
    )
    private lazy var landingWindow = LandingWindowController(
        onSkip: { [weak self] in self?.finishLanding() },
        onFirstFrame: onLandingFirstFrame
    )
    private lazy var statusItemController = StatusItemController(
        onToggleOverlay: { [weak self] in self?.toggleOverlay() },
        onFocusMessage: { [weak self] in self?.focusMessageField() },
        onSelectRoom: { [weak self] roomID in self?.selectRoom(roomID) },
        onToggleQuietMode: { [weak self] in self?.setQuietMode(!(self?.model.preferences.quietModeEnabled ?? false)) },
        onOpenHistory: { [weak self] in self?.showHistory() },
        onToggleLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin(!(self?.model.launchAtLogin ?? false)) },
        onOpenGroupSettings: { [weak self] in self?.showGroupSettings() },
        onOpenSettings: { [weak self] in self?.showSettings() },
        onQuit: { NSApplication.shared.terminate(nil) }
    )
    private var landingTask: Task<Void, Never>?
    private var backendTask: Task<Void, Never>?
    private var backendEventTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var bubbleExpiryTask: Task<Void, Never>?
    private var landingDidComplete = false
    private var didCompleteFirstRunTransition = false
    private var backendBootstrapState: BackendBootstrapState = .pending
    private var typingLease = TypingLease()
    private lazy var activityMonitor = SystemActivityMonitor { [weak self] state in
        self?.localPresenceChanged(state)
    }
    private let mainThreadProbe = MainThreadPerformanceProbe()

    init(
        preferencesStore: PreferencesStore = .live,
        legacyMigrator: LegacySettingsMigrator = .live,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        onLandingFirstFrame: @escaping () -> Void = {}
    ) {
        self.preferencesStore = preferencesStore
        self.legacyMigrator = legacyMigrator
        self.onLandingFirstFrame = onLandingFirstFrame
        let preferences = legacyMigrator.migrateIfNeeded(preferencesStore)
        self.launchReason = LaunchRouter.reason(
            hasShownNativeLanding: preferences.hasShownNativeLanding,
            arguments: arguments
        )
        self.model = AppModel(preferences: preferences)
        do {
            let configuration = try RuntimeConfiguration.resolve()
            self.backend = SideyBackend(configuration: configuration)
            self.configurationError = nil
        } catch {
            self.backend = nil
            self.configurationError = error
        }
    }

    func start() {
        mainThreadProbe.start()
        statusItemController.install()
        overlayWindows.restore(preference: model.preferences.overlayRegion)
        model.launchAtLogin = launchAtLoginController.isEnabled
        model.preferences.launchAtLogin = model.launchAtLogin

        // Overlay rendering is gated on both completed onboarding and a restored
        // backend session. Keep the user's persisted visibility request intact
        // while the runtime windows remain hidden during bootstrap.
        applyRequestedOverlayVisibility()

        switch launchReason {
        case .firstRun:
            refreshStatusItem()
            showLanding()
        case .manual:
            refreshStatusItem()
            showSettings()
        case .loginItem:
            refreshStatusItem()
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        activityMonitor.start()
        startBackend()
    }

    func handleManualReopen() {
        guard model.preferences.hasShownNativeLanding else { return }
        showSettings()
    }

    func shutdown() {
        landingTask?.cancel()
        backendTask?.cancel()
        backendEventTask?.cancel()
        typingTask?.cancel()
        bubbleExpiryTask?.cancel()
        activityMonitor.stop()
        mainThreadProbe.stop()
        if let backend { Task { await backend.shutdown() } }
        persistPreferences()
    }

    private func showLanding() {
        NSApplication.shared.setActivationPolicy(.regular)
        landingWindow.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
        landingTask?.cancel()
        landingTask = Task { [weak self] in
            let configured = ProcessInfo.processInfo.environment["SIDEY_LANDING_DURATION_SECONDS"]
                .flatMap(Double.init) ?? 2
            try? await Task.sleep(for: .seconds(max(0.1, configured)))
            guard !Task.isCancelled else { return }
            self?.finishLanding()
        }
    }

    private func finishLanding() {
        guard launchReason == .firstRun, !landingDidComplete else { return }
        landingDidComplete = true
        landingTask?.cancel()
        landingTask = nil
        model.preferences.hasShownNativeLanding = true
        persistPreferences()
        advanceFirstRunTransition()
    }

    private func advanceFirstRunTransition() {
        guard launchReason == .firstRun, !didCompleteFirstRunTransition else { return }
        let destination = FirstRunTransition.destination(
            landingCompleted: landingDidComplete,
            onboardingComplete: model.preferences.onboardingComplete,
            backendState: backendBootstrapState
        )
        switch destination {
        case .waiting:
            if landingDidComplete, model.preferences.onboardingComplete {
                landingWindow.setRestoringSession(true)
            }
        case .onboarding:
            didCompleteFirstRunTransition = true
            landingWindow.close()
            showSettings()
        case .overlay:
            didCompleteFirstRunTransition = true
            landingWindow.close()
            NSApplication.shared.setActivationPolicy(.accessory)
            applyRequestedOverlayVisibility()
        case .recovery:
            didCompleteFirstRunTransition = true
            landingWindow.close()
            showSettings()
        }
    }

    private func showSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        settingsWindow.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showGroupSettings() {
        model.activeSettingsPage = .groups
        showSettings()
    }

    private func settingsDidClose() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func toggleOverlay() {
        setOverlayVisible(!model.overlayVisible)
    }

    private func focusMessageField() {
        if !model.overlayVisible { setOverlayVisible(true) }
        overlayWindows.focusMessageField()
    }

    private func markActiveRoomRead() {
        guard let roomID = model.activeRoom?.id else { return }
        model.markRoomRead(roomID)
        refreshStatusItem()
    }

    private func setOverlayVisible(_ visible: Bool) {
        model.setOverlayVisibility(OverlayVisibility(isVisible: visible))
        applyRequestedOverlayVisibility()
        refreshStatusItem()
        persistPreferences()
    }

    private func applyRequestedOverlayVisibility() {
        overlayWindows.setVisible(OverlayRevealPolicy.isVisible(
            requested: model.preferences.overlayVisible,
            onboardingComplete: model.preferences.onboardingComplete,
            backendState: backendBootstrapState
        ))
    }

    private func setOverlayRegion(_ preference: OverlayRegionPreference) {
        overlayWindows.setRegionPreference(preference)
        persistPreferences()
    }

    private func setShowOfflineMembers(_ visible: Bool) {
        model.preferences.showOfflineMembers = visible
        persistPreferences()
    }

    private func setQuietMode(_ enabled: Bool) {
        model.preferences.quietModeEnabled = enabled
        if enabled { model.clearBubbles() }
        refreshStatusItem()
        persistPreferences()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            model.launchAtLogin = launchAtLoginController.isEnabled
            model.preferences.launchAtLogin = model.launchAtLogin
            model.errorMessage = nil
            refreshStatusItem()
            persistPreferences()
        } catch {
            model.launchAtLogin = launchAtLoginController.isEnabled
            model.errorMessage = "로그인 자동 실행을 변경하지 못했음: \(error.localizedDescription)"
            refreshStatusItem()
        }
    }

    private func copyInviteCode(roomID: UUID) {
        guard let backend else {
            model.successMessage = nil
            model.errorMessage = "초대 코드를 읽을 서버 구성이 없음"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let inviteCode = try await backend.storedInviteCode(roomID: roomID),
                      !inviteCode.isEmpty
                else {
                    model.successMessage = nil
                    model.errorMessage = "이 기기에 이 그룹의 초대 코드 원문이 없음. 보안상 DB의 해시에서는 복구할 수 없음"
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(inviteCode, forType: .string)
                model.errorMessage = nil
                model.successMessage = "초대 코드를 클립보드에 복사했음"
            } catch {
                model.successMessage = nil
                model.errorMessage = "초대 코드를 읽지 못했음: \(error.localizedDescription)"
            }
        }
    }

    private func refreshStatusItem() {
        statusItemController.update(
            overlayVisible: model.overlayVisible,
            rooms: model.rooms,
            activeRoomID: model.activeRoom?.id,
            unreadCounts: model.unreadCounts,
            quietModeEnabled: model.preferences.quietModeEnabled,
            launchAtLogin: model.launchAtLogin
        )
    }

    private func persistPreferences() {
        preferencesStore.save(model.preferences)
    }

    private func showHistory() {
        markActiveRoomRead()
        NSApplication.shared.setActivationPolicy(.regular)
        historyWindow.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func startBackend() {
        if let configurationError {
            model.connectionState = .failed(configurationError.localizedDescription)
            model.errorMessage = configurationError.localizedDescription
            backendBootstrapState = .failed
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            if launchReason == .loginItem { showSettings() }
            advanceFirstRunTransition()
            return
        }
        guard let backend else {
            backendBootstrapState = .failed
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            if launchReason == .loginItem { showSettings() }
            advanceFirstRunTransition()
            return
        }
        let requireExistingSession = model.preferences.onboardingComplete
        model.connectionState = .connecting
        backendEventTask?.cancel()
        backendEventTask = Task { [weak self] in
            for await event in backend.events {
                guard !Task.isCancelled else { return }
                self?.handleBackendEvent(event)
            }
        }
        backendTask?.cancel()
        backendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await backend.boot(requireExistingSession: requireExistingSession)
                let userID = await backend.currentUserID()
                guard !Task.isCancelled else { return }
                model.apply(snapshot: snapshot, currentUserID: userID)
                try await backend.syncRealtime(
                    roomIDs: snapshot.rooms.map(\.id),
                    activeRoomID: model.activeRoom?.id
                )
                try await loadActiveMessages(from: backend)
                model.connectionState = .online
                model.errorMessage = nil
                backendBootstrapState = .ready
                applyRequestedOverlayVisibility()
                refreshStatusItem()
                persistPreferences()
                advanceFirstRunTransition()
            } catch {
                guard !Task.isCancelled else { return }
                model.connectionState = .failed(error.localizedDescription)
                model.errorMessage = "서버 연결 실패: \(error.localizedDescription)"
                backendBootstrapState = .failed
                applyRequestedOverlayVisibility()
                refreshStatusItem()
                if launchReason == .loginItem { showSettings() }
                advanceFirstRunTransition()
            }
        }
    }

    private func saveProfile() {
        guard let backend else { return }
        let characterID = PixelCharacterCatalog.canonicalID(for: model.selectedCharacterID)
        runMutation {
            _ = try await backend.upsertProfile(
                nickname: self.model.nickname,
                characterID: characterID
            )
        }
    }

    private func createRoom() {
        guard let backend else { return }
        let roomName = model.newRoomName
        let characterID = PixelCharacterCatalog.canonicalID(for: model.selectedCharacterID)
        runMutation {
            _ = try await backend.upsertProfile(
                nickname: self.model.nickname,
                characterID: characterID
            )
            let created = try await backend.createRoom(name: roomName)
            self.model.lastCreatedInviteCode = created.inviteCode
            self.model.newRoomName = ""
            self.model.preferences.activeRoomID = created.roomID
        }
    }

    private func joinRoom() {
        guard let backend else { return }
        let inviteCode = model.inviteCode
        let characterID = PixelCharacterCatalog.canonicalID(for: model.selectedCharacterID)
        runMutation {
            _ = try await backend.upsertProfile(
                nickname: self.model.nickname,
                characterID: characterID
            )
            let roomID = try await backend.joinRoom(inviteCode: inviteCode)
            self.model.inviteCode = ""
            self.model.preferences.activeRoomID = roomID
        }
    }

    private func selectRoom(_ roomID: UUID) {
        overlayWindows.dismissComposer()
        typingChanged(false)
        model.preferences.activeRoomID = roomID
        model.markRoomRead(roomID)
        model.clearBubbles()
        refreshStatusItem()
        persistPreferences()
        if let backend {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await backend.setActiveRoom(roomID)
                    try await loadActiveMessages(from: backend)
                } catch {
                    model.errorMessage = "그룹 전환 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadActiveMessages(from backend: SideyBackend) async throws {
        guard let roomID = model.activeRoom?.id else {
            model.clearBubbles()
            return
        }
        let messages = try await backend.recentMessages(roomID: roomID)
        model.replaceMessages(roomID: roomID, with: messages)
    }

    private func sendMessage(_ body: String) {
        guard let backend, let roomID = model.activeRoom?.id else {
            model.errorMessage = SideyBackendError.noActiveRoom.localizedDescription
            model.draft = body
            overlayWindows.presentComposer()
            return
        }
        guard let senderID = model.currentUserID else {
            model.errorMessage = "현재 사용자 정보를 확인하지 못했음"
            model.draft = body
            overlayWindows.presentComposer()
            return
        }
        let messageID = UUID()
        let revealMessage = !model.preferences.quietModeEnabled
        model.stageMessage(
            id: messageID,
            roomID: roomID,
            senderID: senderID,
            body: body,
            revealBubble: revealMessage
        )
        if revealMessage { scheduleBubbleExpiry() }
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await backend.sendMessage(roomID: roomID, body: body, id: messageID)
                model.confirmMessage(message, revealBubble: revealMessage)
                model.errorMessage = nil
            } catch {
                model.errorMessage = "전송 실패: \(error.localizedDescription)"
                model.draft = model.failMessage(id: messageID) ?? body
                overlayWindows.presentComposer()
            }
        }
    }

    private func runMutation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard let backend else { return }
        Task { [weak self] in
            guard let self else { return }
            model.isWorking = true
            model.successMessage = nil
            defer { model.isWorking = false }
            do {
                let wasOnboardingComplete = model.preferences.onboardingComplete
                try await operation()
                let snapshot = try await backend.loadSnapshot()
                model.apply(snapshot: snapshot, currentUserID: await backend.currentUserID())
                try await backend.syncRealtime(
                    roomIDs: snapshot.rooms.map(\.id),
                    activeRoomID: model.activeRoom?.id
                )
                try await loadActiveMessages(from: backend)
                model.connectionState = .online
                model.errorMessage = nil
                if !wasOnboardingComplete && model.preferences.onboardingComplete {
                    model.activeSettingsPage = .groups
                    settingsWindow.transitionFromOnboardingToSettings()
                }
                applyRequestedOverlayVisibility()
                refreshStatusItem()
                persistPreferences()
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleBackendEvent(_ event: BackendEvent) {
        switch event {
        case .snapshot(let snapshot):
            model.apply(snapshot: snapshot, currentUserID: model.currentUserID)
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            persistPreferences()
            if let backend {
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await backend.syncRealtime(
                            roomIDs: snapshot.rooms.map(\.id),
                            activeRoomID: model.activeRoom?.id
                        )
                        try await loadActiveMessages(from: backend)
                    } catch {
                        model.connectionState = .failed(error.localizedDescription)
                    }
                }
            }
        case .message(let message):
            let isActiveRoom = message.roomID == model.activeRoom?.id
            let revealMessage = isActiveRoom && !model.preferences.quietModeEnabled
            let isNew = model.confirmMessage(message, revealBubble: revealMessage)
            guard isNew else { return }
            if message.senderID != model.currentUserID && (!isActiveRoom || model.preferences.quietModeEnabled) {
                model.incrementUnread(in: message.roomID)
            }
            if revealMessage { scheduleBubbleExpiry() }
            refreshStatusItem()
        case .presence(let roomID, let userID, let state):
            model.updatePresence(roomID: roomID, userID: userID, state: state)
        case .typing(let roomID, let userID, let active):
            model.updateTyping(roomID: roomID, userID: userID, active: active)
        case .connection(let connected):
            model.connectionState = connected ? .online : .connecting
            model.setRealtimeConnected(connected)
        }
    }

    private func scheduleBubbleExpiry() {
        bubbleExpiryTask?.cancel()
        bubbleExpiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                model.dismissExpiredBubbles()
                if model.activeBubbles.isEmpty { return }
            }
        }
    }

    private func localPresenceChanged(_ state: PresenceState) {
        model.presence = state
        guard let backend else { return }
        Task {
            do { try await backend.setLocalPresence(state) }
            catch { model.connectionState = .failed(error.localizedDescription) }
        }
    }

    private func typingChanged(_ active: Bool) {
        if let roomID = model.activeRoom?.id, let userID = model.currentUserID {
            model.updateTyping(roomID: roomID, userID: userID, active: active)
        }
        guard let backend else { return }
        let actions = typingLease.update(active: active, roomID: model.activeRoom?.id)
        for action in actions {
            switch action {
            case .stop(let stoppedRoomID):
                typingTask?.cancel()
                typingTask = nil
                Task { try? await backend.broadcastTyping(roomID: stoppedRoomID, event: "typing_stop") }
            case .start(let startedRoomID):
                typingTask?.cancel()
                typingTask = Task {
                    try? await backend.broadcastTyping(roomID: startedRoomID, event: "typing_start")
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        try? await backend.broadcastTyping(roomID: startedRoomID, event: "typing_keepalive")
                    }
                }
            }
        }
    }
}

@MainActor
private final class MainThreadPerformanceProbe: NSObject {
    private static let interval = 1.0 / 60.0
    private let outputURL = ProcessInfo.processInfo.environment["SIDEY_MAIN_THREAD_METRICS_PATH"]
        .map { URL(fileURLWithPath: $0) }
    private var timer: Timer?
    private var previousTick: CFTimeInterval?
    private var tickGapsMS: [Double] = []

    func start() {
        guard outputURL != nil, timer == nil else { return }
        previousTick = CACurrentMediaTime()
        let timer = Timer(
            timeInterval: Self.interval,
            target: self,
            selector: #selector(tick(_:)),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        flush()
    }

    @objc private func tick(_ timer: Timer) {
        let now = CACurrentMediaTime()
        if let previousTick {
            tickGapsMS.append((now - previousTick) * 1_000)
        }
        previousTick = now
        if !tickGapsMS.isEmpty && tickGapsMS.count.isMultiple(of: 300) {
            flush()
        }
    }

    private func flush() {
        guard let outputURL else { return }
        let sorted = tickGapsMS.sorted()
        let p95Index = sorted.isEmpty
            ? 0
            : min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        let maximumGap = sorted.last ?? 0
        let snapshot = MainThreadMetricsSnapshot(
            sampleCount: tickGapsMS.count,
            tickGapP95MS: sorted.isEmpty ? 0 : sorted[p95Index],
            tickGapMaxMS: maximumGap,
            maximumStallMS: max(0, maximumGap - Self.interval * 1_000)
        )
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: outputURL, options: .atomic)
        }
    }
}

private struct MainThreadMetricsSnapshot: Codable, Sendable {
    let sampleCount: Int
    let tickGapP95MS: Double
    let tickGapMaxMS: Double
    let maximumStallMS: Double
}
