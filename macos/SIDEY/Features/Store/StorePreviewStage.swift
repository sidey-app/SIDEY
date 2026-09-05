import AppKit
import SpriteKit
import SwiftUI

enum StorePreviewStageLayout {
    static let size = CGSize(width: 540, height: 280)
    static let platformHeight: CGFloat = 24
    static let platformPixelSize: CGFloat = 4
}

struct StorePreviewStage: View {
    let product: CommerceProduct

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playbackOverride: Bool?

    private var scenario: StorePreviewScenario {
        StorePreviewScenario.make(product: product)
    }

    private var isPlaying: Bool {
        playbackOverride ?? !reduceMotion
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                StorePreviewPlatform()
                StorePreviewSceneView(scenario: scenario, isPlaying: isPlaying)
                    .accessibilityLabel("\(product.displayName) 동적 미리보기")
                    .accessibilityHint("캐릭터를 두 번 클릭하면 확대 반응을 볼 수 있습니다.")
            }
            .frame(width: StorePreviewStageLayout.size.width, height: StorePreviewStageLayout.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }

            Button {
                playbackOverride = !isPlaying
            } label: {
                Label(
                    isPlaying ? "미리보기 일시 정지" : "미리보기 재생",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPlaying ? "상품 미리보기 일시 정지" : "상품 미리보기 재생")
        }
    }
}

private struct StorePreviewPlatform: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let pixel = StorePreviewStageLayout.platformPixelSize
            let base = colorScheme == .dark
                ? Color(red: 0.20, green: 0.21, blue: 0.23)
                : Color(red: 0.72, green: 0.73, blue: 0.75)
            let alternate = colorScheme == .dark
                ? Color(red: 0.25, green: 0.26, blue: 0.28)
                : Color(red: 0.80, green: 0.81, blue: 0.83)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            let columns = Int(ceil(size.width / pixel))
            let rows = Int(ceil(size.height / pixel))
            for row in 0..<rows where row.isMultiple(of: 2) {
                for column in 0..<columns where column.isMultiple(of: 2) == row.isMultiple(of: 4) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * pixel,
                            y: CGFloat(row) * pixel,
                            width: pixel,
                            height: pixel
                        )),
                        with: .color(alternate)
                    )
                }
            }
        }
        .frame(height: StorePreviewStageLayout.platformHeight)
        .accessibilityHidden(true)
    }
}

private struct StorePreviewSceneView: NSViewRepresentable {
    let scenario: StorePreviewScenario
    let isPlaying: Bool

    func makeCoordinator() -> StorePreviewPlaybackCoordinator {
        StorePreviewPlaybackCoordinator()
    }

    func makeNSView(context: Context) -> StorePreviewSKView {
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        PixelWorldRendererPolicy.apply(to: view)
        let scene = PixelWorldScene(
            size: StorePreviewStageLayout.size,
            renderingConfiguration: .storePreview(
                fixedTrackFractions: scenario.fixedTrackFractions
            )
        )
        scene.scaleMode = .resizeFill
        apply(scenario, to: scene)
        view.presentScene(scene)
        context.coordinator.configure(
            view: view,
            scene: scene,
            scenario: scenario,
            isPlaying: isPlaying
        )
        return view
    }

    func updateNSView(_ view: StorePreviewSKView, context: Context) {
        guard let scene = view.scene as? PixelWorldScene else { return }
        apply(scenario, to: scene)
        context.coordinator.configure(
            view: view,
            scene: scene,
            scenario: scenario,
            isPlaying: isPlaying
        )
    }

    static func dismantleNSView(
        _ view: StorePreviewSKView,
        coordinator: StorePreviewPlaybackCoordinator
    ) {
        coordinator.stop(detachingScene: true)
    }

    private func apply(_ scenario: StorePreviewScenario, to scene: PixelWorldScene) {
        scene.apply(
            roomID: StorePreviewScenario.roomID,
            members: scenario.members,
            bubbles: scenario.bubbles,
            edge: .bottom,
            activityFrame: CGRect(
                x: 0,
                y: StorePreviewStageLayout.platformHeight,
                width: StorePreviewStageLayout.size.width,
                height: StorePreviewStageLayout.size.height - StorePreviewStageLayout.platformHeight
            ),
            installationSeed: 0x51_DE_59,
            onCharacterFramesChanged: { _ in }
        )
    }
}

@MainActor
final class StorePreviewPlaybackCoordinator {
    private weak var view: StorePreviewSKView?
    private weak var scene: PixelWorldScene?
    private var productID: String?
    private(set) var throwTask: Task<Void, Never>?

    var hasActiveThrowTask: Bool { throwTask != nil }

    func configure(
        view: StorePreviewSKView,
        scene: PixelWorldScene,
        scenario: StorePreviewScenario,
        isPlaying: Bool
    ) {
        let changedScene = self.scene !== scene || productID != scenario.productID
        if changedScene {
            stop(detachingScene: false)
            self.view = view
            self.scene = scene
            productID = scenario.productID
        }
        view.isPaused = !isPlaying
        guard isPlaying, let sequence = scenario.throwSequence else {
            cancelThrowTask()
            scene.cancelLocalPreviewPlayback()
            return
        }
        guard throwTask == nil else { return }
        throwTask = Task { @MainActor [weak scene] in
            do {
                let startedAt = ProcessInfo.processInfo.systemUptime
                var index = 0
                while !Task.isCancelled {
                    let deadline = startedAt + sequence.scheduledOffset(for: index)
                    let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                    try await Task.sleep(for: .seconds(delay))
                    scene?.playLocalPreviewThrow(sequence.event(at: index))
                    index += 1
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func stop(detachingScene: Bool) {
        cancelThrowTask()
        scene?.cancelLocalPreviewPlayback()
        if detachingScene {
            view?.presentScene(nil)
            view?.isPaused = true
            view = nil
            scene = nil
            productID = nil
        } else {
            view?.isPaused = true
        }
    }

    private func cancelThrowTask() {
        throwTask?.cancel()
        throwTask = nil
    }

    deinit {
        throwTask?.cancel()
    }
}

final class StorePreviewSKView: SKView {
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, !isPaused, let scene = scene as? PixelWorldScene else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        _ = scene.playLocalPreviewPulse(at: scene.convertPoint(fromView: viewPoint))
    }
}
