import AVFoundation
import Flutter
import UIKit

class IOSSpatialAudioBridge: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let bridge = IOSSpatialAudioBridge()
        let channel = FlutterMethodChannel(name: SpatialAudioChannelContract.methodChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(bridge, channel: channel)
    }

    private var engine: AVAudioEngine?
    private var environmentNode: AVAudioEnvironmentNode?
    private var eventPlayer: AVAudioPlayerNode?
    private var isInitialized = false
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case SpatialAudioChannelContract.getCapabilitiesMethod:
            result([SpatialAudioChannelContract.supportsSpatialKey: true])
        case SpatialAudioChannelContract.updateOffRouteAlertMethod:
            updateSpatialPosition(args: call.arguments as? [String: Any] ?? [:])
            result(nil)
        case SpatialAudioChannelContract.stopOffRouteAlertMethod:
            eventPlayer?.stop()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func updateSpatialPosition(args: [String: Any]) {
        do {
            try ensureInitialized()
            let relAngle = (args[SpatialAudioChannelContract.relativeAngleDegKey] as? NSNumber)?.floatValue ?? 0
            let dist = (args[SpatialAudioChannelContract.sourceDistanceMetersKey] as? NSNumber)?.floatValue ?? 2.0
            let rad = relAngle * .pi / 180.0
            eventPlayer?.position = AVAudio3DPoint(x: sin(rad) * dist, y: 0, z: -cos(rad) * dist)
            if let p = eventPlayer, !p.isPlaying { p.play() }
        } catch {
            print("SpatialAudioBridge Error: \(error)")
        }
    }
    
    private func ensureInitialized() throws {
        if isInitialized { return }
        let newEngine = AVAudioEngine()
        let newEnv = AVAudioEnvironmentNode()
        let newPlayer = AVAudioPlayerNode()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        newEngine.attach(newEnv)
        newEngine.attach(newPlayer)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        newEngine.connect(newPlayer, to: newEnv, format: format)
        newEngine.connect(newEnv, to: newEngine.mainMixerNode, format: newEngine.outputNode.inputFormat(forBus: 0))
        newPlayer.renderingAlgorithm = .HRTFHQ
        try newEngine.start()
        self.engine = newEngine
        self.environmentNode = newEnv
        self.eventPlayer = newPlayer
        self.isInitialized = true
    }
}
