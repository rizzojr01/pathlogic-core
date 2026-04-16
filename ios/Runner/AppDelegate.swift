import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register custom bridges using standard Plugin registration
    // This is safer and avoids rootViewController timing issues
    IOSArTrackingBridge.register(with: self.registrar(forPlugin: "com.unav.pathlogic.ArBridge")!)
    IOSSpatialAudioBridge.register(with: self.registrar(forPlugin: "com.unav.pathlogic.AudioBridge")!)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
