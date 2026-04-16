import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register custom bridges
    setupCustomPlugins()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupCustomPlugins() {
    // Safety check: ensure registrar is available
    if let arRegistrar = self.registrar(forPlugin: "ArTrackingPlugin") {
        IOSArTrackingBridge.register(with: arRegistrar)
    }
    
    if let audioRegistrar = self.registrar(forPlugin: "SpatialAudioPlugin") {
        IOSSpatialAudioBridge.register(with: audioRegistrar)
    }
  }
}
