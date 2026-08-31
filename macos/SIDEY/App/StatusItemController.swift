import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let onToggleOverlay: () -> Void
    private let onToggleInteraction: () -> Void
    private let onFocusMessage: () -> Void
    private let onSelectRoom: (UUID) -> Void
    private let onToggleQuietMode: () -> Void
    private let onResetOverlayPosition: () -> Void
    private let onToggleLaunchAtLogin: () -> Void
    private let onOpenGroupSettings: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private var statusItem: NSStatusItem?
    private var overlayVisible = true
    private var overlayMode: OverlayMode = .locked
    private var rooms: [Room] = []
    private var activeRoomID: UUID?
    private var unreadCounts: [UUID: Int] = [:]
    private var quietModeEnabled = false
    private var launchAtLogin = false

    init(
        onToggleOverlay: @escaping () -> Void,
        onToggleInteraction: @escaping () -> Void,
        onFocusMessage: @escaping () -> Void = {},
        onSelectRoom: @escaping (UUID) -> Void = { _ in },
        onToggleQuietMode: @escaping () -> Void = {},
        onResetOverlayPosition: @escaping () -> Void = {},
        onToggleLaunchAtLogin: @escaping () -> Void = {},
        onOpenGroupSettings: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggleOverlay = onToggleOverlay
        self.onToggleInteraction = onToggleInteraction
        self.onFocusMessage = onFocusMessage
        self.onSelectRoom = onSelectRoom
        self.onToggleQuietMode = onToggleQuietMode
        self.onResetOverlayPosition = onResetOverlayPosition
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.onOpenGroupSettings = onOpenGroupSettings
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "person.2.wave.2", accessibilityDescription: "SIDEY")
        item.menu = makeMenu()
        statusItem = item
    }

    func update(
        overlayVisible: Bool,
        overlayMode: OverlayMode,
        rooms: [Room] = [],
        activeRoomID: UUID? = nil,
        unreadCounts: [UUID: Int] = [:],
        quietModeEnabled: Bool = false,
        launchAtLogin: Bool = false
    ) {
        self.overlayVisible = overlayVisible
        self.overlayMode = overlayMode
        self.rooms = rooms
        self.activeRoomID = activeRoomID
        self.unreadCounts = unreadCounts
        self.quietModeEnabled = quietModeEnabled
        self.launchAtLogin = launchAtLogin
        updateStatusIcon()
        statusItem?.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "SIDEY")
        let overlay = NSMenuItem(
            title: overlayVisible ? "오버레이 숨기기" : "오버레이 보이기",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        overlay.target = self
        menu.addItem(overlay)

        let message = NSMenuItem(title: "메시지 작성…", action: #selector(focusMessage), keyEquivalent: "")
        message.target = self
        message.isEnabled = !rooms.isEmpty
        menu.addItem(message)

        let interaction = NSMenuItem(
            title: overlayMode == .locked ? "오버레이 잠금 해제" : "오버레이 잠금",
            action: #selector(toggleInteraction),
            keyEquivalent: ""
        )
        interaction.target = self
        interaction.isEnabled = overlayVisible
        menu.addItem(interaction)
        menu.addItem(.separator())

        let groups = NSMenuItem(title: "활성 그룹", action: nil, keyEquivalent: "")
        groups.submenu = makeRoomsMenu()
        groups.isEnabled = !rooms.isEmpty
        menu.addItem(groups)

        let quiet = NSMenuItem(title: "조용히 모드", action: #selector(toggleQuietMode), keyEquivalent: "")
        quiet.target = self
        quiet.state = quietModeEnabled ? .on : .off
        menu.addItem(quiet)

        let reset = NSMenuItem(title: "오버레이 위치 초기화", action: #selector(resetOverlayPosition), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = overlayVisible
        menu.addItem(reset)

        let groupSettings = NSMenuItem(title: "그룹 설정…", action: #selector(openGroupSettings), keyEquivalent: "")
        groupSettings.target = self
        menu.addItem(groupSettings)

        let login = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "SIDEY 종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func makeRoomsMenu() -> NSMenu {
        let menu = NSMenu(title: "활성 그룹")
        if rooms.isEmpty {
            let empty = NSMenuItem(title: "연결된 그룹 없음", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }
        for room in rooms {
            let unread = unreadCounts[room.id, default: 0]
            let suffix = unread > 0 ? " (\(unread))" : ""
            let item = NSMenuItem(
                title: room.name + suffix,
                action: #selector(selectRoom(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = room.id.uuidString
            item.state = room.id == activeRoomID ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func updateStatusIcon() {
        let hasUnread = unreadCounts.values.contains(where: { $0 > 0 })
        statusItem?.button?.image = NSImage(
            systemSymbolName: "person.2.wave.2",
            accessibilityDescription: hasUnread ? "SIDEY, 읽지 않은 메시지 있음" : "SIDEY"
        )
        statusItem?.button?.toolTip = hasUnread ? "SIDEY · 읽지 않은 메시지 있음" : "SIDEY"
    }

    @objc private func toggleOverlay() { onToggleOverlay() }
    @objc private func toggleInteraction() { onToggleInteraction() }
    @objc private func focusMessage() { onFocusMessage() }
    @objc private func selectRoom(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String, let roomID = UUID(uuidString: rawID) else { return }
        onSelectRoom(roomID)
    }
    @objc private func toggleQuietMode() { onToggleQuietMode() }
    @objc private func resetOverlayPosition() { onResetOverlayPosition() }
    @objc private func toggleLaunchAtLogin() { onToggleLaunchAtLogin() }
    @objc private func openGroupSettings() { onOpenGroupSettings() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { onQuit() }
}
