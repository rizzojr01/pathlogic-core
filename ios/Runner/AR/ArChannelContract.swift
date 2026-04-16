import Foundation

/// Constants for Flutter ↔ AR Native communication
enum ArChannelContract {
    static let methodChannel = "unav/tracking/ar_method"
    static let eventChannel = "unav/tracking/ar_pose_stream"
    static let previewViewType = "unav/tracking/ar_preview_view"
    
    // Methods
    static let startSessionMethod = "startSession"
    static let stopSessionMethod = "stopSession"
    static let getCapabilitiesMethod = "getCapabilities"
    static let captureCurrentFrameMethod = "captureCurrentFrame"
    static let updateOverlayMethod = "updateOverlay"
    static let clearOverlayMethod = "clearOverlay"
    
    // Keys
    static let backendKey = "backend"
    static let isSupportedKey = "isSupported"
    static let xKey = "x"
    static let yKey = "y"
    static let zKey = "z"
    static let headingKey = "heading"
    static let confidenceKey = "confidence"
    static let timestampKey = "timestampMillis"
    
    static let activePathPointsKey = "activePathPoints"
    static let futurePathPointsKey = "futurePathPoints"
    static let nextWaypointKey = "nextWaypoint"
    static let destinationKey = "destination"
}
