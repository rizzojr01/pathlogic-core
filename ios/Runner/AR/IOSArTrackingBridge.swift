import ARKit
import Flutter
import UIKit
import SceneKit

class IOSArTrackingBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    static func register(with registrar: FlutterPluginRegistrar) {
        let bridge = IOSArTrackingBridge()
        bridge.setupChannels(with: registrar)
        registrar.register(IOSArPreviewFactory(bridge: bridge), withId: ArChannelContract.previewViewType)
    }

    let session = ARSession()
    private lazy var ciContext = CIContext()
    private var eventSink: FlutterEventSink?
    private var isSessionRunning = false
    private var latestFrame: ARFrame?
    private let previewViews = NSHashTable<ARSCNView>.weakObjects()
    private let overlayRootNode = SCNNode()

    override init() {
        super.init()
        session.delegate = self
        overlayRootNode.name = "unav_overlay_root"
    }

    private func setupChannels(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: ArChannelContract.methodChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(self, channel: methodChannel)

        let eventChannel = FlutterEventChannel(name: ArChannelContract.eventChannel, binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(self)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case ArChannelContract.getCapabilitiesMethod:
            result([
                ArChannelContract.backendKey: "iosArKit",
                ArChannelContract.isSupportedKey: ARWorldTrackingConfiguration.isSupported
            ])
        case ArChannelContract.startSessionMethod:
            startSession(result: result)
        case ArChannelContract.stopSessionMethod:
            stopSession()
            result(nil)
        case ArChannelContract.captureCurrentFrameMethod:
            captureCurrentFrame(result: result)
        case ArChannelContract.updateOverlayMethod:
            updateOverlay(arguments: call.arguments)
            result(nil)
        case ArChannelContract.clearOverlayMethod:
            clearOverlay()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startSession(result: FlutterResult) {
        guard ARWorldTrackingConfiguration.isSupported else {
            result(FlutterError(code: "arkit_unsupported", message: "ARKit unavailable", details: nil))
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: isSessionRunning ? [] : [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        result(nil)
    }

    private func stopSession() {
        if isSessionRunning { session.pause(); isSessionRunning = false }
    }

    private func captureCurrentFrame(result: FlutterResult) {
        guard let frame = latestFrame else {
            result(FlutterError(code: "frame_unavailable", message: nil, details: nil))
            return
        }
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            result(FlutterError(code: "conv_failed", message: nil, details: nil))
            return
        }
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        result(FlutterStandardTypedData(bytes: uiImage.jpegData(compressionQuality: 0.9) ?? Data()))
    }

    func attachPreviewView(_ sceneView: ARSCNView) {
        previewViews.add(sceneView)
        if overlayRootNode.parent == nil {
            sceneView.scene.rootNode.addChildNode(overlayRootNode)
        }
    }

    private func clearOverlay() {
        overlayRootNode.childNodes.forEach { $0.removeFromParentNode() }
    }

    private func updateOverlay(arguments: Any?) {
        guard let args = arguments as? [String: Any] else { clearOverlay(); return }
        clearOverlay()
        let activePathPoints = (args[ArChannelContract.activePathPointsKey] as? [[String: Any]] ?? []).compactMap { parsePoint($0) }
        if activePathPoints.count >= 2 {
            for i in 0..<(activePathPoints.count - 1) {
                overlayRootNode.addChildNode(buildPathSegment(from: activePathPoints[i], to: activePathPoints[i+1]))
            }
        }
    }

    private func parsePoint(_ dict: [String: Any]) -> SCNVector3? {
        guard let x = dict[ArChannelContract.xKey] as? NSNumber, let y = dict[ArChannelContract.yKey] as? NSNumber, let z = dict[ArChannelContract.zKey] as? NSNumber else { return nil }
        return SCNVector3(x.floatValue, y.floatValue, z.floatValue)
    }

    private func buildPathSegment(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z
        let distance = sqrt(dx*dx + dy*dy + dz*dz)
        let cylinder = SCNCylinder(radius: 0.035, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.9)
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
        node.eulerAngles = SCNVector3(Float.pi/2 - atan2(dy, sqrt(dx*dx + dz*dz)), atan2(dx, dz), 0)
        return node
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

extension IOSArTrackingBridge: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
        guard let eventSink = eventSink else { return }
        let transform = frame.camera.transform
        let translation = transform.columns.3
        let cameraForward = SIMD3<Float>(-transform.columns.2.x, -transform.columns.2.y, -transform.columns.2.z)
        let headingRad = atan2(Double(-cameraForward.z), Double(cameraForward.x))
        var headingDeg = headingRad * 180.0 / .pi
        if headingDeg < 0 { headingDeg += 360.0 }

        eventSink([
            ArChannelContract.xKey: Double(translation.x),
            ArChannelContract.yKey: Double(-translation.z),
            ArChannelContract.zKey: Double(translation.y),
            ArChannelContract.headingKey: headingDeg,
            ArChannelContract.confidenceKey: frame.camera.trackingState == .normal ? 1.0 : 0.5,
            ArChannelContract.timestampKey: Int(Date().timeIntervalSince1970 * 1000.0)
        ])
    }
}
