import Foundation
import ARKit

/// Utility for detecting device capabilities for facial analysis
struct DeviceCapabilities {

    /// Check if the device supports TrueDepth camera (Face ID devices)
    /// Required for ARKit face tracking with 52 blend shapes
    static var supportsTrueDepthCamera: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    /// Check if basic Vision face detection is available (all iOS devices)
    static var supportsVisionFaceDetection: Bool {
        // Vision framework is available on iOS 11+, which is always true for SwiftUI apps
        true
    }

    /// Determine the best analysis mode for this device
    static var recommendedAnalysisMode: AnalysisMode {
        if supportsTrueDepthCamera {
            return .visionAndARKit
        } else if supportsVisionFaceDetection {
            return .visionOnly
        } else {
            return .none
        }
    }

    /// Human-readable device capability description
    static var capabilityDescription: String {
        if supportsTrueDepthCamera {
            return "Full facial analysis with 52 muscle tracking points"
        } else {
            return "Basic facial analysis with pose and quality detection"
        }
    }

    /// List of features available on this device
    static var availableFeatures: [String] {
        var features = [
            "Face detection",
            "Face quality assessment",
            "Head pose tracking",
            "Eye openness detection"
        ]

        if supportsTrueDepthCamera {
            features.append(contentsOf: [
                "52 blend shape tracking",
                "Detailed eye tracking",
                "Brow tension detection",
                "Smile/frown intensity",
                "Jaw position tracking",
                "Facial symmetry analysis"
            ])
        }

        return features
    }
}
