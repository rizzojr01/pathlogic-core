import Foundation

enum SpatialAudioChannelContract {
    static let methodChannel = "unav/audio/spatial_method"
    static let getCapabilitiesMethod = "getCapabilities"
    static let playCueMethod = "playCue"
    static let updateOffRouteAlertMethod = "updateOffRouteAlert"
    static let stopOffRouteAlertMethod = "stopOffRouteAlert"
    
    // Keys
    static let supportsSpatialKey = "supportsSpatial"
    static let relativeAngleDegKey = "relativeAngleDeg"
    static let sourceDistanceMetersKey = "sourceDistanceMeters"
}
