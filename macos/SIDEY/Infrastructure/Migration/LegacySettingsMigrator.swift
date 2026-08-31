import Foundation

struct LegacySettingsMigrator: Sendable {
    var migrateIfNeeded: @Sendable (PreferencesStore) -> AppPreferences

    static let live: LegacySettingsMigrator = {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return .files([
            support?.appending(path: "Godot/app_userdata/SIDEY/settings.json"),
            support?.appending(path: "SIDEY/settings.json")
        ].compactMap { $0 })
    }()

    static func files(_ candidates: [URL]) -> LegacySettingsMigrator {
        LegacySettingsMigrator { store in
            let current = store.load()
            guard current == .defaults else { return current }

            let manager = FileManager.default
            guard let url = candidates.first(where: { manager.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return current }

            // Godot schema v2+ stores profile/rooms/onboarding under `local_state`.
            // Keep the root fallback for pre-schema and development builds.
            let localState = root["local_state"] as? [String: Any] ?? root

            var migrated = current
            if let profile = localState["profile"] as? [String: Any] {
                migrated.nickname = profile["nickname"] as? String ?? migrated.nickname
            }
            if let activeRoom = localState["active_room_id"] as? String {
                migrated.activeRoomID = UUID(uuidString: activeRoom)
            } else if let rooms = root["rooms"] as? [String: Any],
               let activeRoom = rooms["active_room_id"] as? String {
                migrated.activeRoomID = UUID(uuidString: activeRoom)
            }
            if let overlay = root["overlay"] as? [String: Any] {
                migrated.overlayVisible = overlay["visible"] as? Bool ?? migrated.overlayVisible
                migrated.overlayLocked = overlay["locked"] as? Bool ?? migrated.overlayLocked
                migrated.overlayScale = Self.number(overlay["scale"]) ?? migrated.overlayScale
                if let signature = overlay["screen_signature"] as? String, !signature.isEmpty {
                    migrated.overlayScreenIdentifier = signature
                    migrated.overlayRegion.screenIdentifier = signature
                }
                if let position = overlay["position"] as? [Any], position.count >= 2,
                   let x = Self.number(position[0]), let y = Self.number(position[1]) {
                    migrated.overlayFrame = CodableRect(
                        CGRect(x: x, y: y, width: 720, height: 360)
                    )
                }
            }
            migrated.schemaVersion = AppPreferences.currentSchemaVersion
            migrated.overlayRegion.edge = .bottom
            migrated.overlayRegion.span = .full
            migrated.onboardingComplete = localState["onboarding_complete"] as? Bool
                ?? migrated.onboardingComplete
            store.save(migrated)
            return migrated
        }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static let none = LegacySettingsMigrator { store in store.load() }
}
