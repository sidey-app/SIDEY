import CryptoKit
import Foundation
import RealityKit
import SceneKit
import XCTest
@testable import SIDEY

@MainActor
final class MintyPupAssetTests: XCTestCase {
    func testAllRuntimeClipsLoadWithAnimation() async throws {
        for motion in CharacterMotion.allCases {
            let url = try XCTUnwrap(MintyPupScene.assetURL(for: motion))
            let entity = try await Entity(contentsOf: url)
            XCTAssertTrue(containsAnimation(entity), "\(motion.resourceName)에 애니메이션이 없음")
        }
    }

    func testAllRuntimeClipsLoadInSceneKitAtTheExpectedOrientation() throws {
        for motion in CharacterMotion.allCases {
            let scene = try MintyPupScene.makeScene(motion: motion)
            let modelRoot = try XCTUnwrap(
                scene.rootNode.childNode(withName: MintyPupScene.modelRootName, recursively: false)
            )
            XCTAssertEqual(modelRoot.eulerAngles.x, -.pi / 2, accuracy: 0.0001)
            XCTAssertTrue(containsSceneKitAnimation(scene.rootNode), "\(motion.resourceName)에 SceneKit 애니메이션이 없음")
            let geometryNodes = descendants(of: modelRoot).filter { $0.geometry != nil }
            XCTAssertFalse(geometryNodes.isEmpty, "\(motion.resourceName)에 geometry가 없음")
            XCTAssertTrue(
                geometryNodes.allSatisfy { !($0.geometry?.materials.isEmpty ?? true) },
                "\(motion.resourceName)에 재질 없는 geometry가 있음"
            )
            let skinners = descendants(of: modelRoot).compactMap(\.skinner)
            XCTAssertFalse(skinners.isEmpty, "\(motion.resourceName)에 skinning rig가 없음")
            XCTAssertTrue(skinners.allSatisfy { !$0.bones.isEmpty }, "\(motion.resourceName)에 bone 없는 skinner가 있음")
            let lights = descendants(of: scene.rootNode).compactMap(\.light)
            XCTAssertTrue(lights.allSatisfy { !$0.castsShadow }, "실시간 그림자가 활성화됨")
        }
    }

    func testExportReportLocksRigMaterialAndThirtyFPSContract() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: "export-report",
                withExtension: "json",
                subdirectory: "Characters/MintyPup"
            ) ?? Bundle.main.url(forResource: "export-report", withExtension: "json")
        )
        let report = try JSONDecoder().decode(ExportReport.self, from: Data(contentsOf: url))

        XCTAssertEqual(
            report.source,
            "assets/characters/dog/minty_pup_station_v3_animated.glb"
        )
        XCTAssertEqual(report.sourceSHA256.count, 64)

        XCTAssertEqual(report.clips.count, 3)
        XCTAssertEqual(Set(report.clips.map(\.track)), ["online_idle", "typing", "away_sleep"])
        for clip in report.clips {
            XCTAssertEqual(clip.validation.bones, 19)
            XCTAssertEqual(clip.validation.triangles, 22_248)
            XCTAssertEqual(
                Set(clip.validation.materials),
                ["LaptopSilver", "StationCream", "StationDark", "material"]
            )
            XCTAssertFalse(clip.validation.animationTracks.isEmpty)
            XCTAssertEqual(clip.validation.fps, 30)
            XCTAssertEqual(clip.validation.textureDimensions, ["512x512"])
            XCTAssertEqual(clip.usdchecker, "Success!")
            let assetName = (clip.file as NSString).deletingPathExtension
            let assetURL = try XCTUnwrap(
                Bundle.main.url(
                    forResource: assetName,
                    withExtension: "usdz",
                    subdirectory: "Characters/MintyPup"
                ) ?? Bundle.main.url(forResource: assetName, withExtension: "usdz")
            )
            XCTAssertEqual(
                try assetURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                clip.bytes
            )
            XCTAssertEqual(try sha256(of: assetURL), clip.sha256)
        }
        XCTAssertEqual(Set(report.clips.map { $0.validation.headPoseSignature }).count, 3)
    }

    private func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func containsAnimation(_ entity: Entity) -> Bool {
        if !entity.availableAnimations.isEmpty { return true }
        return entity.children.contains(where: containsAnimation)
    }

    private func containsSceneKitAnimation(_ node: SCNNode) -> Bool {
        if !node.animationKeys.isEmpty { return true }
        return node.childNodes.contains(where: containsSceneKitAnimation)
    }

    private func descendants(of node: SCNNode) -> [SCNNode] {
        [node] + node.childNodes.flatMap(descendants)
    }
}

private struct ExportReport: Decodable {
    let source: String
    let sourceSHA256: String
    let clips: [Clip]

    struct Clip: Decodable {
        let file: String
        let bytes: Int
        let sha256: String
        let track: String
        let validation: Validation
        let usdchecker: String
    }

    enum CodingKeys: String, CodingKey {
        case source, clips
        case sourceSHA256 = "source_sha256"
    }

    struct Validation: Decodable {
        let bones: Int
        let triangles: Int
        let materials: [String]
        let animationTracks: [String]
        let fps: Int
        let textureDimensions: [String]
        let headPoseSignature: [Double]

        enum CodingKeys: String, CodingKey {
            case bones, triangles, materials, fps
            case animationTracks = "animation_tracks"
            case textureDimensions = "texture_dimensions"
            case headPoseSignature = "head_pose_signature"
        }
    }
}
