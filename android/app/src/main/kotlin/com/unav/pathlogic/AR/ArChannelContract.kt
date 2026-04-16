package com.unav.pathlogic.AR

object ArChannelContract {
    const val AR_METHOD_CHANNEL = "unav/tracking/ar_method"
    const val AR_POSE_EVENT_CHANNEL = "unav/tracking/ar_pose_stream"
    const val AR_PREVIEW_VIEW_TYPE = "unav/tracking/ar_preview_view"

    const val START_SESSION_METHOD = "startSession"
    const val STOP_SESSION_METHOD = "stopSession"
    const val GET_CAPABILITIES_METHOD = "getCapabilities"
    const val CAPTURE_CURRENT_FRAME_METHOD = "captureCurrentFrame"
    const val UPDATE_OVERLAY_METHOD = "updateOverlay"
    const val CLEAR_OVERLAY_METHOD = "clearOverlay"

    const val BACKEND_KEY = "backend"
    const val IS_SUPPORTED_KEY = "isSupported"
    const val X_KEY = "x"
    const val Y_KEY = "y"
    const val Z_KEY = "z"
    const val HEADING_KEY = "heading"
    const val CONFIDENCE_KEY = "confidence"
    const val TIMESTAMP_KEY = "timestampMillis"
    const val WORLD_X_KEY = "worldX"
    const val WORLD_Y_KEY = "worldY"
    const val WORLD_Z_KEY = "worldZ"
    const val GRAVITY_X_KEY = "gravityX"
    const val GRAVITY_Y_KEY = "gravityY"
    const val GRAVITY_Z_KEY = "gravityZ"
    const val INTERFACE_ROTATION_DEG_KEY = "interfaceRotationDeg"

    const val ACTIVE_PATH_POINTS_KEY = "activePathPoints"
    const val FUTURE_PATH_POINTS_KEY = "futurePathPoints"
    const val NEXT_WAYPOINT_KEY = "nextWaypoint"
    const val DESTINATION_KEY = "destination"
}
