import ARKit
import Flutter
import UIKit

class IOSArPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let bridge: IOSArTrackingBridge
    
    init(bridge: IOSArTrackingBridge) {
        self.bridge = bridge
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return IOSArPreviewPlatformView(frame: frame, bridge: bridge)
    }
}

class IOSArPreviewPlatformView: NSObject, FlutterPlatformView {
    private let sceneView: ARSCNView
    
    init(frame: CGRect, bridge: IOSArTrackingBridge) {
        sceneView = ARSCNView(frame: frame)
        super.init()
        
        // Configure SceneView
        sceneView.automaticallyUpdatesLighting = true
        sceneView.rendersContinuously = true
        sceneView.scene = SCNScene()
        sceneView.session = bridge.session
        
        // Link with bridge for overlay rendering
        bridge.attachPreviewView(sceneView)
    }
    
    func view() -> UIView {
        return sceneView
    }
}
