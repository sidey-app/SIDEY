import AppKit
import Metal
import SceneKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: render_usdz_snapshot.swift input.usdz output.png\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let imported = try SCNScene(
    url: input,
    options: [.animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly]
)
let scene = SCNScene()
scene.background.contents = NSColor(calibratedWhite: 0.055, alpha: 1)

let modelRoot = SCNNode()
modelRoot.position = SCNVector3(0, -0.45, 0)
modelRoot.eulerAngles.x = -.pi / 2
for child in imported.rootNode.childNodes {
    child.removeFromParentNode()
    modelRoot.addChildNode(child)
}
scene.rootNode.addChildNode(modelRoot)

let camera = SCNNode()
camera.camera = SCNCamera()
camera.camera?.fieldOfView = 32
camera.position = SCNVector3(0, 1.25, 2.15)
camera.look(at: SCNVector3(0, 0.72, -0.08))
scene.rootNode.addChildNode(camera)

let key = SCNNode()
key.light = SCNLight()
key.light?.type = .directional
key.light?.intensity = 620
key.light?.color = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.86, alpha: 1)
key.light?.castsShadow = false
key.eulerAngles = SCNVector3(-0.65, -0.55, 0)
scene.rootNode.addChildNode(key)

let ambient = SCNNode()
ambient.light = SCNLight()
ambient.light?.type = .ambient
ambient.light?.intensity = 230
ambient.light?.color = NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 1)
scene.rootNode.addChildNode(ambient)

guard let device = MTLCreateSystemDefaultDevice() else {
    throw NSError(domain: "SIDEY", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"])
}
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = camera
renderer.isPlaying = true
let image = renderer.snapshot(
    atTime: 1.0,
    with: CGSize(width: 840, height: 600),
    antialiasingMode: .none
)
guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    throw NSError(domain: "SIDEY", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
}
try png.write(to: output, options: .atomic)
print("SIDEY_USDZ_SNAPSHOT=\(output.path)")
