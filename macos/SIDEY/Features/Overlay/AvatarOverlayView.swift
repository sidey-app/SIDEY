import QuartzCore
import SceneKit
import SwiftUI

struct AvatarOverlayView: View {
    @Bindable var model: AppModel
    @State private var projectedHeadTop: CGFloat = AvatarOverlayLayout.fallbackProjectedHeadTop

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                SceneKitAvatarView(
                    motion: motion,
                    scale: Float(model.preferences.overlayScale / 1.5),
                    onProjectedHeadTopChanged: { headTop in
                        guard abs(projectedHeadTop - headTop) > 0.5 else { return }
                        projectedHeadTop = headTop
                    }
                )
                .frame(width: AvatarOverlayLayout.contentWidth, height: AvatarOverlayLayout.sceneHeight)
                .offset(y: AvatarOverlayLayout.sceneYOffset)

                if let message = model.latestMessage {
                    Text(message)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                        .frame(maxWidth: 360)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(
                            width: AvatarOverlayLayout.contentWidth,
                            height: AvatarOverlayLayout.bubbleBottom(for: projectedHeadTop),
                            alignment: .bottom
                        )
                        .frame(
                            width: AvatarOverlayLayout.contentWidth,
                            height: AvatarOverlayLayout.contentHeight,
                            alignment: .top
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: AvatarOverlayLayout.contentWidth, height: AvatarOverlayLayout.contentHeight)

            VStack(spacing: 10) {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(presenceColor)
                        .frame(width: 9, height: 9)
                    Text(model.displayedMember?.nickname ?? model.nickname)
                        .font(.headline)
                    if model.activeRoomUnreadCount > 0 {
                        Circle()
                            .fill(.cyan)
                            .frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.62), in: Capsule())
                .padding(.bottom, 70)
            }
            .frame(width: AvatarOverlayLayout.contentWidth, height: AvatarOverlayLayout.contentHeight)
        }
        .frame(
            width: AvatarOverlayLayout.contentWidth,
            height: AvatarOverlayLayout.contentHeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: -AvatarOverlayLayout.bottomInset)
        .animation(.spring(duration: 0.3), value: model.latestMessage)
        .accessibilityHidden(true)
    }

    private var presenceColor: Color {
        PresenceIndicatorTone.tone(for: model.avatarPresence).color
    }

    private var motion: CharacterMotion {
        switch model.avatarPresence {
        case .typing: .typing
        case .away, .offline, .reconnecting: .offlineSleep
        case .online: .onlineIdle
        }
    }
}

enum PresenceIndicatorTone: Equatable {
    case green
    case orange
    case red
    case gray

    static func tone(for state: PresenceState) -> Self {
        switch state {
        case .online, .typing: .green
        case .away: .orange
        case .offline: .red
        case .reconnecting: .gray
        }
    }

    var color: Color {
        switch self {
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .gray: .gray
        }
    }
}

enum AvatarOverlayLayout {
    static let contentWidth: CGFloat = 420
    static let contentHeight: CGFloat = 340
    static let sceneHeight: CGFloat = 300
    static let sceneYOffset: CGFloat = -8
    static let bottomInset: CGFloat = 10
    static let topWindowExtension: CGFloat = 180
    static let fallbackProjectedHeadTop: CGFloat = 48
    private static let sceneTopInContent = (contentHeight - sceneHeight) / 2 + sceneYOffset
    private static let bubbleGap: CGFloat = 10

    static func bubbleBottom(for projectedHeadTop: CGFloat) -> CGFloat {
        max(1, sceneTopInContent + projectedHeadTop - bubbleGap)
    }

    @MainActor
    static func projectedHeadTop(of modelRoot: SCNNode, in view: SCNView) -> CGFloat? {
        guard view.bounds.height > 0 else { return nil }
        let bounds = modelRoot.boundingBox
        let corners = [bounds.min.x, bounds.max.x].flatMap { x in
            [bounds.min.y, bounds.max.y].flatMap { y in
                [bounds.min.z, bounds.max.z].map { z in SCNVector3(x, y, z) }
            }
        }
        let projectedTops = corners.compactMap { corner -> CGFloat? in
            let worldPoint = modelRoot.convertPosition(corner, to: nil)
            let projected = view.projectPoint(worldPoint)
            let top = view.bounds.height - CGFloat(projected.y)
            return top.isFinite ? top : nil
        }
        return projectedTops.min()
    }
}

@MainActor
enum AvatarRendererPolicy {
    static let preferredFramesPerSecond = 30

    static func apply(to view: SCNView) {
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.rendersContinuously = true
        view.antialiasingMode = .none
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.loops = true
    }
}

private struct SceneKitAvatarView: NSViewRepresentable {
    let motion: CharacterMotion
    let scale: Float
    let onProjectedHeadTopChanged: @MainActor (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProjectedHeadTopChanged: onProjectedHeadTopChanged)
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.contentsScale = 1
        AvatarRendererPolicy.apply(to: view)
        view.delegate = context.coordinator.metrics
        context.coordinator.apply(motion: motion, scale: scale, to: view)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.onProjectedHeadTopChanged = onProjectedHeadTopChanged
        context.coordinator.apply(motion: motion, scale: scale, to: view)
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.cancelLoading()
        view.isPlaying = false
        coordinator.metrics.flush()
        view.scene = nil
        view.pointOfView = nil
    }

    @MainActor
    final class Coordinator {
        let metrics = RenderMetricsProbe()
        var onProjectedHeadTopChanged: @MainActor (CGFloat) -> Void
        private var requestedMotion: CharacterMotion?
        private var requestedScale: Float = 1
        private var loadTask: Task<Void, Never>?
        private var anchorTask: Task<Void, Never>?
        private var lastProjectedHeadTop: CGFloat?

        init(onProjectedHeadTopChanged: @escaping @MainActor (CGFloat) -> Void) {
            self.onProjectedHeadTopChanged = onProjectedHeadTopChanged
        }

        func apply(motion: CharacterMotion, scale: Float, to view: SCNView) {
            requestedScale = scale
            let existingRoot = view.scene?.rootNode.childNode(
                withName: MintyPupScene.modelRootName,
                recursively: false
            )
            existingRoot?.scale = SCNVector3(scale, scale, scale)
            if existingRoot != nil { scheduleHeadAnchorUpdate(in: view) }

            guard requestedMotion != motion else { return }
            requestedMotion = motion
            loadTask?.cancel()
            loadTask = Task { @MainActor [weak self, weak view] in
                let loaded = await Task.detached(priority: .userInitiated) {
                    SceneLoadResult {
                        try MintyPupScene.makeScene(motion: motion)
                    }
                }.value
                guard
                    !Task.isCancelled,
                    let self,
                    let view,
                    self.requestedMotion == motion
                else { return }

                let scene = loaded.scene ?? MintyPupScene.makeFallbackScene()
                scene.rootNode.childNode(
                    withName: MintyPupScene.modelRootName,
                    recursively: false
                )?.scale = SCNVector3(requestedScale, requestedScale, requestedScale)
                view.scene = scene
                view.pointOfView = scene.rootNode.childNode(
                    withName: MintyPupScene.cameraName,
                    recursively: false
                )
                view.isPlaying = true
                self.scheduleHeadAnchorUpdate(in: view)
            }
        }

        func cancelLoading() {
            loadTask?.cancel()
            loadTask = nil
            anchorTask?.cancel()
            anchorTask = nil
        }

        private func scheduleHeadAnchorUpdate(in view: SCNView) {
            anchorTask?.cancel()
            anchorTask = Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard
                    !Task.isCancelled,
                    let self,
                    let view,
                    view.bounds.height > 0,
                    let root = view.scene?.rootNode.childNode(
                        withName: MintyPupScene.modelRootName,
                        recursively: false
                    ),
                    let headTop = AvatarOverlayLayout.projectedHeadTop(of: root, in: view)
                else { return }
                if let lastProjectedHeadTop, abs(lastProjectedHeadTop - headTop) <= 0.5 { return }
                lastProjectedHeadTop = headTop
                onProjectedHeadTopChanged(headTop)
            }
        }
    }
}

private struct SceneLoadResult: @unchecked Sendable {
    let scene: SCNScene?

    init(_ load: () throws -> SCNScene) {
        scene = try? load()
    }
}

private final class RenderMetricsProbe: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let outputURL = ProcessInfo.processInfo.environment["SIDEY_RENDER_METRICS_PATH"]
        .map { URL(fileURLWithPath: $0) }
    private let lock = NSLock()
    private var previousFrameTime: TimeInterval?
    private var renderStartTime: CFTimeInterval?
    private var frameIntervalsMS: [Double] = []
    private var renderDurationsMS: [Double] = []

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard outputURL != nil else { return }
        lock.lock()
        if let previousFrameTime {
            frameIntervalsMS.append((time - previousFrameTime) * 1_000)
        }
        previousFrameTime = time
        lock.unlock()
    }

    func renderer(
        _ renderer: any SCNSceneRenderer,
        willRenderScene scene: SCNScene,
        atTime time: TimeInterval
    ) {
        guard outputURL != nil else { return }
        lock.lock()
        renderStartTime = CACurrentMediaTime()
        lock.unlock()
    }

    func renderer(
        _ renderer: any SCNSceneRenderer,
        didRenderScene scene: SCNScene,
        atTime time: TimeInterval
    ) {
        guard outputURL != nil else { return }
        let now = CACurrentMediaTime()
        var shouldFlush = false
        lock.lock()
        if let renderStartTime {
            renderDurationsMS.append((now - renderStartTime) * 1_000)
        }
        self.renderStartTime = nil
        shouldFlush = !frameIntervalsMS.isEmpty && frameIntervalsMS.count.isMultiple(of: 300)
        lock.unlock()
        if shouldFlush { flush() }
    }

    func flush() {
        guard let outputURL else { return }
        let snapshot: RenderMetricsSnapshot
        lock.lock()
        snapshot = RenderMetricsSnapshot(
            frameIntervalsMS: frameIntervalsMS,
            renderDurationsMS: renderDurationsMS
        )
        lock.unlock()
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: outputURL, options: .atomic)
        }
    }
}

private struct RenderMetricsSnapshot: Codable, Sendable {
    let sampleCount: Int
    let frameIntervalP95MS: Double
    let frameIntervalMaxMS: Double
    let renderDurationP95MS: Double
    let renderDurationMaxMS: Double
    let frameIntervalsMS: [Double]
    let renderDurationsMS: [Double]

    init(frameIntervalsMS: [Double], renderDurationsMS: [Double]) {
        sampleCount = frameIntervalsMS.count
        frameIntervalP95MS = Self.percentile95(frameIntervalsMS)
        frameIntervalMaxMS = frameIntervalsMS.max() ?? 0
        renderDurationP95MS = Self.percentile95(renderDurationsMS)
        renderDurationMaxMS = renderDurationsMS.max() ?? 0
        self.frameIntervalsMS = frameIntervalsMS
        self.renderDurationsMS = renderDurationsMS
    }

    private static func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }
}

enum CharacterMotion: String, CaseIterable, Sendable {
    case onlineIdle
    case typing
    case offlineSleep

    var resourceName: String {
        switch self {
        case .onlineIdle: "MintyPupOnlineIdle"
        case .typing: "MintyPupTyping"
        case .offlineSleep: "MintyPupOfflineSleep"
        }
    }
}

enum MintyPupScene {
    static let cameraName = "sidey_minty_pup_camera"
    static let modelRootName = "sidey_minty_pup_model"

    static func assetURL(for motion: CharacterMotion, bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: motion.resourceName,
            withExtension: "usdz",
            subdirectory: "Characters/MintyPup"
        ) ?? bundle.url(forResource: motion.resourceName, withExtension: "usdz")
    }

    static func makeScene(motion: CharacterMotion) throws -> SCNScene {
        guard let url = assetURL(for: motion) else {
            throw MintyPupAssetError.missing(motion.resourceName)
        }
        let imported = try SCNScene(
            url: url,
            options: [
                .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly
            ]
        )
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let modelRoot = SCNNode()
        modelRoot.name = modelRootName
        modelRoot.position = SCNVector3(0, -0.45, 0)
        modelRoot.eulerAngles.x = -.pi / 2
        for child in imported.rootNode.childNodes {
            child.removeFromParentNode()
            modelRoot.addChildNode(child)
        }
        scene.rootNode.addChildNode(modelRoot)
        installCameraAndLights(in: scene)
        return scene
    }

    static func makeFallbackScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let modelRoot = SCNNode(geometry: SCNSphere(radius: 0.42))
        modelRoot.name = modelRootName
        modelRoot.geometry?.firstMaterial?.diffuse.contents = NSColor.systemMint
        installCameraAndLights(in: scene)
        scene.rootNode.addChildNode(modelRoot)
        return scene
    }

    private static func installCameraAndLights(in scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.name = cameraName
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 32
        // Keep the overlay front-facing and crop below the desktop. The model
        // root has already converted Blender Z-up to SceneKit Y-up here.
        cameraNode.position = SCNVector3(0, 1.25, 2.15)
        cameraNode.look(at: SCNVector3(0, 0.72, -0.08))
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 620
        keyLight.light?.color = NSColor(
            calibratedRed: 1.0,
            green: 0.94,
            blue: 0.86,
            alpha: 1
        )
        keyLight.light?.castsShadow = false
        keyLight.eulerAngles = SCNVector3(-0.65, -0.55, 0)
        scene.rootNode.addChildNode(keyLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 230
        ambientLight.light?.color = NSColor(
            calibratedRed: 0.90,
            green: 0.94,
            blue: 1.0,
            alpha: 1
        )
        scene.rootNode.addChildNode(ambientLight)
    }
}

enum MintyPupAssetError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name): "3D asset missing: \(name)"
        }
    }
}
