import CoreGraphics
import Foundation

struct CodableRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var schemaVersion = 4
    var hasShownNativeLanding = false
    var onboardingComplete = false
    var overlayVisible = true
    var overlayLocked = true
    var overlayScale = 1.5
    var quietModeEnabled = false
    var launchAtLogin = false
    var overlayFrame: CodableRect?
    var overlayScreenIdentifier: String?
    var nickname = "나"
    var activeRoomID: UUID?

    static let defaults = AppPreferences()

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hasShownNativeLanding
        case onboardingComplete
        case overlayVisible
        case overlayLocked
        case overlayScale
        case quietModeEnabled
        case launchAtLogin
        case overlayFrame
        case overlayScreenIdentifier
        case nickname
        case activeRoomID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        hasShownNativeLanding = try values.decodeIfPresent(Bool.self, forKey: .hasShownNativeLanding) ?? false
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        overlayVisible = try values.decodeIfPresent(Bool.self, forKey: .overlayVisible) ?? true
        overlayLocked = try values.decodeIfPresent(Bool.self, forKey: .overlayLocked) ?? true
        overlayScale = try values.decodeIfPresent(Double.self, forKey: .overlayScale) ?? 1.5
        quietModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .quietModeEnabled) ?? false
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        overlayFrame = try values.decodeIfPresent(CodableRect.self, forKey: .overlayFrame)
        overlayScreenIdentifier = try values.decodeIfPresent(String.self, forKey: .overlayScreenIdentifier)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? "나"
        activeRoomID = try values.decodeIfPresent(UUID.self, forKey: .activeRoomID)
    }
}

struct PreferencesStore: Sendable {
    var load: @Sendable () -> AppPreferences
    var save: @Sendable (AppPreferences) -> Void

    static let live = PreferencesStore(
        load: {
            guard let data = UserDefaults.standard.data(forKey: "sidey.preferences"),
                  let value = try? JSONDecoder().decode(AppPreferences.self, from: data)
            else { return .defaults }
            return value
        },
        save: { value in
            guard let data = try? JSONEncoder().encode(value) else { return }
            UserDefaults.standard.set(data, forKey: "sidey.preferences")
        }
    )

    static func userDefaults(_ defaults: UserDefaults) -> PreferencesStore {
        let box = UserDefaultsBox(defaults)
        return PreferencesStore(
            load: {
                guard let data = box.value.data(forKey: "sidey.preferences"),
                      let value = try? JSONDecoder().decode(AppPreferences.self, from: data)
                else { return .defaults }
                return value
            },
            save: { value in
                guard let data = try? JSONEncoder().encode(value) else { return }
                box.value.set(data, forKey: "sidey.preferences")
            }
        )
    }
}

private final class UserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults
    init(_ value: UserDefaults) { self.value = value }
}
