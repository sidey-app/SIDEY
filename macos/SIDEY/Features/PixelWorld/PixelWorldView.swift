import SpriteKit
import SwiftUI

struct PixelWorldView: View {
    @Bindable var model: AppModel
    let composerVisible: Bool
    let characterPulse: CharacterPulseEvent?
    let onCurrentUserFrameChanged: (CGRect?) -> Void

    var body: some View {
        PixelWorldRepresentable(
            roomID: model.activeRoom?.id,
            members: model.pixelWorldMembers,
            bubbles: model.activeBubbles,
            edge: model.preferences.overlayRegion.edge,
            installationSeed: model.preferences.installationSeed,
            composerVisible: composerVisible,
            characterPulse: characterPulse,
            onCurrentUserFrameChanged: onCurrentUserFrameChanged
        )
    }
}

private struct PixelWorldRepresentable: NSViewRepresentable {
    let roomID: UUID?
    let members: [PixelWorldMember]
    let bubbles: [ActiveBubble]
    let edge: OverlayEdge
    let installationSeed: UInt64
    let composerVisible: Bool
    let characterPulse: CharacterPulseEvent?
    let onCurrentUserFrameChanged: (CGRect?) -> Void

    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        PixelWorldRendererPolicy.apply(to: view)
        let scene = PixelWorldScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        apply(to: scene)
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        guard let scene = view.scene as? PixelWorldScene else { return }
        apply(to: scene)
        view.isPaused = false
    }

    static func dismantleNSView(_ view: SKView, coordinator: Void) {
        view.isPaused = true
        view.presentScene(nil)
    }

    private func apply(to scene: PixelWorldScene) {
        scene.apply(
            roomID: roomID,
            members: members,
            bubbles: bubbles,
            edge: edge,
            installationSeed: installationSeed,
            composerVisible: composerVisible,
            characterPulse: characterPulse,
            onCurrentUserFrameChanged: onCurrentUserFrameChanged
        )
    }
}
