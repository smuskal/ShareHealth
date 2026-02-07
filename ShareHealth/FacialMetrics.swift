import Foundation

// MARK: - Main Facial Metrics Container

/// Complete facial analysis results combining Vision and ARKit data
struct FacialMetrics: Codable {
    let captureTimestamp: Date
    let analysisVersion: String
    let analysisMode: AnalysisMode
    let healthIndicators: FacialHealthIndicators
    let visionMetrics: VisionFaceMetrics?
    let arkitMetrics: ARKitFaceMetrics?

    static let currentVersion = "1.0"

    init(
        captureTimestamp: Date = Date(),
        analysisMode: AnalysisMode,
        healthIndicators: FacialHealthIndicators,
        visionMetrics: VisionFaceMetrics? = nil,
        arkitMetrics: ARKitFaceMetrics? = nil
    ) {
        self.captureTimestamp = captureTimestamp
        self.analysisVersion = Self.currentVersion
        self.analysisMode = analysisMode
        self.healthIndicators = healthIndicators
        self.visionMetrics = visionMetrics
        self.arkitMetrics = arkitMetrics
    }
}

// MARK: - Analysis Mode

enum AnalysisMode: String, Codable {
    case visionOnly = "visionOnly"
    case visionAndARKit = "visionAndARKit"
    case none = "none"
}

// MARK: - Health Indicators (Computed Scores)

/// Derived health-relevant scores from facial analysis
struct FacialHealthIndicators: Codable {
    /// 0-100: Eye openness, wideness, brow position, head posture
    let alertnessScore: Double

    /// 0-100: Brow tension, jaw clenching, eye squint
    let tensionScore: Double

    /// 0-100: Smile intensity, frown detection
    let smileScore: Double

    /// 0-100: Left/right balance across features
    let facialSymmetry: Double

    /// 0-100: Quality indicator for trusting metrics (face quality, lighting, pose)
    let captureReliabilityScore: Double

    /// Average of all scores weighted by reliability
    var overallScore: Double {
        let weights = [0.3, 0.2, 0.2, 0.15, 0.15]  // alertness, tension(inverted), smile, symmetry, reliability
        let invertedTension = 100.0 - tensionScore  // Lower tension is better
        let scores = [alertnessScore, invertedTension, smileScore, facialSymmetry, captureReliabilityScore]
        return zip(weights, scores).map { $0 * $1 }.reduce(0, +)
    }

    static let empty = FacialHealthIndicators(
        alertnessScore: 0,
        tensionScore: 0,
        smileScore: 0,
        facialSymmetry: 0,
        captureReliabilityScore: 0
    )
}

// MARK: - Vision Framework Metrics

/// Metrics extracted from Vision framework face detection
struct VisionFaceMetrics: Codable {
    /// Overall face detection quality (0-1)
    let faceQuality: Double

    /// Head rotation around z-axis (tilt left/right) in radians
    let roll: Double

    /// Head rotation around x-axis (look up/down) in radians
    let pitch: Double

    /// Head rotation around y-axis (look left/right) in radians
    let yaw: Double

    /// Left eye openness (0 = closed, 1 = fully open)
    let leftEyeOpenness: Double

    /// Right eye openness (0 = closed, 1 = fully open)
    let rightEyeOpenness: Double

    /// Bounding box of face in normalized coordinates
    let faceBoundingBox: CodableBoundingBox

    /// Number of landmarks detected
    let landmarkCount: Int

    // Computed properties
    var averageEyeOpenness: Double {
        (leftEyeOpenness + rightEyeOpenness) / 2.0
    }

    var eyeSymmetry: Double {
        1.0 - abs(leftEyeOpenness - rightEyeOpenness)
    }

    var headPoseScore: Double {
        // Score based on how centered the head is (0-1, higher is more centered)
        let rollScore = 1.0 - min(abs(roll) / 0.5, 1.0)
        let pitchScore = 1.0 - min(abs(pitch) / 0.5, 1.0)
        let yawScore = 1.0 - min(abs(yaw) / 0.5, 1.0)
        return (rollScore + pitchScore + yawScore) / 3.0
    }

    /// Convert radians to degrees for display
    var rollDegrees: Double { roll * 180.0 / .pi }
    var pitchDegrees: Double { pitch * 180.0 / .pi }
    var yawDegrees: Double { yaw * 180.0 / .pi }
}

// MARK: - ARKit Blend Shapes

/// All 52 ARKit blend shape coefficients
struct ARKitFaceMetrics: Codable {
    // Eye expressions
    let eyeBlinkLeft: Double
    let eyeBlinkRight: Double
    let eyeLookDownLeft: Double
    let eyeLookDownRight: Double
    let eyeLookInLeft: Double
    let eyeLookInRight: Double
    let eyeLookOutLeft: Double
    let eyeLookOutRight: Double
    let eyeLookUpLeft: Double
    let eyeLookUpRight: Double
    let eyeSquintLeft: Double
    let eyeSquintRight: Double
    let eyeWideLeft: Double
    let eyeWideRight: Double

    // Eyebrow expressions
    let browDownLeft: Double
    let browDownRight: Double
    let browInnerUp: Double
    let browOuterUpLeft: Double
    let browOuterUpRight: Double

    // Jaw expressions
    let jawForward: Double
    let jawLeft: Double
    let jawRight: Double
    let jawOpen: Double

    // Mouth expressions
    let mouthClose: Double
    let mouthFunnel: Double
    let mouthPucker: Double
    let mouthLeft: Double
    let mouthRight: Double
    let mouthSmileLeft: Double
    let mouthSmileRight: Double
    let mouthFrownLeft: Double
    let mouthFrownRight: Double
    let mouthDimpleLeft: Double
    let mouthDimpleRight: Double
    let mouthStretchLeft: Double
    let mouthStretchRight: Double
    let mouthRollLower: Double
    let mouthRollUpper: Double
    let mouthShrugLower: Double
    let mouthShrugUpper: Double
    let mouthPressLeft: Double
    let mouthPressRight: Double
    let mouthLowerDownLeft: Double
    let mouthLowerDownRight: Double
    let mouthUpperUpLeft: Double
    let mouthUpperUpRight: Double

    // Cheek and nose
    let cheekPuff: Double
    let cheekSquintLeft: Double
    let cheekSquintRight: Double
    let noseSneerLeft: Double
    let noseSneerRight: Double

    // Tongue (available on some devices)
    let tongueOut: Double

    // MARK: - Computed Properties

    var averageSmile: Double {
        (mouthSmileLeft + mouthSmileRight) / 2.0
    }

    var averageFrown: Double {
        (mouthFrownLeft + mouthFrownRight) / 2.0
    }

    var averageBlink: Double {
        (eyeBlinkLeft + eyeBlinkRight) / 2.0
    }

    var averageEyeWide: Double {
        (eyeWideLeft + eyeWideRight) / 2.0
    }

    var averageSquint: Double {
        (eyeSquintLeft + eyeSquintRight) / 2.0
    }

    var averageBrowDown: Double {
        (browDownLeft + browDownRight) / 2.0
    }

    var jawTension: Double {
        // Combine jaw clenching indicators
        let jawClenching = 1.0 - jawOpen  // Closed jaw indicates tension
        let jawPushing = jawForward
        return (jawClenching + jawPushing) / 2.0
    }

    /// Calculate left-right symmetry across all paired features
    var overallSymmetry: Double {
        let pairs: [(Double, Double)] = [
            (eyeBlinkLeft, eyeBlinkRight),
            (eyeSquintLeft, eyeSquintRight),
            (eyeWideLeft, eyeWideRight),
            (browDownLeft, browDownRight),
            (browOuterUpLeft, browOuterUpRight),
            (mouthSmileLeft, mouthSmileRight),
            (mouthFrownLeft, mouthFrownRight),
            (cheekSquintLeft, cheekSquintRight),
            (noseSneerLeft, noseSneerRight)
        ]

        let symmetryScores = pairs.map { 1.0 - abs($0.0 - $0.1) }
        return symmetryScores.reduce(0, +) / Double(symmetryScores.count)
    }

    /// Get all blend shapes as a dictionary for JSON export
    var allBlendShapes: [String: Double] {
        [
            "eyeBlinkLeft": eyeBlinkLeft,
            "eyeBlinkRight": eyeBlinkRight,
            "eyeLookDownLeft": eyeLookDownLeft,
            "eyeLookDownRight": eyeLookDownRight,
            "eyeLookInLeft": eyeLookInLeft,
            "eyeLookInRight": eyeLookInRight,
            "eyeLookOutLeft": eyeLookOutLeft,
            "eyeLookOutRight": eyeLookOutRight,
            "eyeLookUpLeft": eyeLookUpLeft,
            "eyeLookUpRight": eyeLookUpRight,
            "eyeSquintLeft": eyeSquintLeft,
            "eyeSquintRight": eyeSquintRight,
            "eyeWideLeft": eyeWideLeft,
            "eyeWideRight": eyeWideRight,
            "browDownLeft": browDownLeft,
            "browDownRight": browDownRight,
            "browInnerUp": browInnerUp,
            "browOuterUpLeft": browOuterUpLeft,
            "browOuterUpRight": browOuterUpRight,
            "jawForward": jawForward,
            "jawLeft": jawLeft,
            "jawRight": jawRight,
            "jawOpen": jawOpen,
            "mouthClose": mouthClose,
            "mouthFunnel": mouthFunnel,
            "mouthPucker": mouthPucker,
            "mouthLeft": mouthLeft,
            "mouthRight": mouthRight,
            "mouthSmileLeft": mouthSmileLeft,
            "mouthSmileRight": mouthSmileRight,
            "mouthFrownLeft": mouthFrownLeft,
            "mouthFrownRight": mouthFrownRight,
            "mouthDimpleLeft": mouthDimpleLeft,
            "mouthDimpleRight": mouthDimpleRight,
            "mouthStretchLeft": mouthStretchLeft,
            "mouthStretchRight": mouthStretchRight,
            "mouthRollLower": mouthRollLower,
            "mouthRollUpper": mouthRollUpper,
            "mouthShrugLower": mouthShrugLower,
            "mouthShrugUpper": mouthShrugUpper,
            "mouthPressLeft": mouthPressLeft,
            "mouthPressRight": mouthPressRight,
            "mouthLowerDownLeft": mouthLowerDownLeft,
            "mouthLowerDownRight": mouthLowerDownRight,
            "mouthUpperUpLeft": mouthUpperUpLeft,
            "mouthUpperUpRight": mouthUpperUpRight,
            "cheekPuff": cheekPuff,
            "cheekSquintLeft": cheekSquintLeft,
            "cheekSquintRight": cheekSquintRight,
            "noseSneerLeft": noseSneerLeft,
            "noseSneerRight": noseSneerRight,
            "tongueOut": tongueOut
        ]
    }

    /// Create from ARKit blend shape dictionary
    static func from(blendShapes: [String: Double]) -> ARKitFaceMetrics {
        ARKitFaceMetrics(
            eyeBlinkLeft: blendShapes["eyeBlinkLeft"] ?? 0,
            eyeBlinkRight: blendShapes["eyeBlinkRight"] ?? 0,
            eyeLookDownLeft: blendShapes["eyeLookDownLeft"] ?? 0,
            eyeLookDownRight: blendShapes["eyeLookDownRight"] ?? 0,
            eyeLookInLeft: blendShapes["eyeLookInLeft"] ?? 0,
            eyeLookInRight: blendShapes["eyeLookInRight"] ?? 0,
            eyeLookOutLeft: blendShapes["eyeLookOutLeft"] ?? 0,
            eyeLookOutRight: blendShapes["eyeLookOutRight"] ?? 0,
            eyeLookUpLeft: blendShapes["eyeLookUpLeft"] ?? 0,
            eyeLookUpRight: blendShapes["eyeLookUpRight"] ?? 0,
            eyeSquintLeft: blendShapes["eyeSquintLeft"] ?? 0,
            eyeSquintRight: blendShapes["eyeSquintRight"] ?? 0,
            eyeWideLeft: blendShapes["eyeWideLeft"] ?? 0,
            eyeWideRight: blendShapes["eyeWideRight"] ?? 0,
            browDownLeft: blendShapes["browDownLeft"] ?? 0,
            browDownRight: blendShapes["browDownRight"] ?? 0,
            browInnerUp: blendShapes["browInnerUp"] ?? 0,
            browOuterUpLeft: blendShapes["browOuterUpLeft"] ?? 0,
            browOuterUpRight: blendShapes["browOuterUpRight"] ?? 0,
            jawForward: blendShapes["jawForward"] ?? 0,
            jawLeft: blendShapes["jawLeft"] ?? 0,
            jawRight: blendShapes["jawRight"] ?? 0,
            jawOpen: blendShapes["jawOpen"] ?? 0,
            mouthClose: blendShapes["mouthClose"] ?? 0,
            mouthFunnel: blendShapes["mouthFunnel"] ?? 0,
            mouthPucker: blendShapes["mouthPucker"] ?? 0,
            mouthLeft: blendShapes["mouthLeft"] ?? 0,
            mouthRight: blendShapes["mouthRight"] ?? 0,
            mouthSmileLeft: blendShapes["mouthSmileLeft"] ?? 0,
            mouthSmileRight: blendShapes["mouthSmileRight"] ?? 0,
            mouthFrownLeft: blendShapes["mouthFrownLeft"] ?? 0,
            mouthFrownRight: blendShapes["mouthFrownRight"] ?? 0,
            mouthDimpleLeft: blendShapes["mouthDimpleLeft"] ?? 0,
            mouthDimpleRight: blendShapes["mouthDimpleRight"] ?? 0,
            mouthStretchLeft: blendShapes["mouthStretchLeft"] ?? 0,
            mouthStretchRight: blendShapes["mouthStretchRight"] ?? 0,
            mouthRollLower: blendShapes["mouthRollLower"] ?? 0,
            mouthRollUpper: blendShapes["mouthRollUpper"] ?? 0,
            mouthShrugLower: blendShapes["mouthShrugLower"] ?? 0,
            mouthShrugUpper: blendShapes["mouthShrugUpper"] ?? 0,
            mouthPressLeft: blendShapes["mouthPressLeft"] ?? 0,
            mouthPressRight: blendShapes["mouthPressRight"] ?? 0,
            mouthLowerDownLeft: blendShapes["mouthLowerDownLeft"] ?? 0,
            mouthLowerDownRight: blendShapes["mouthLowerDownRight"] ?? 0,
            mouthUpperUpLeft: blendShapes["mouthUpperUpLeft"] ?? 0,
            mouthUpperUpRight: blendShapes["mouthUpperUpRight"] ?? 0,
            cheekPuff: blendShapes["cheekPuff"] ?? 0,
            cheekSquintLeft: blendShapes["cheekSquintLeft"] ?? 0,
            cheekSquintRight: blendShapes["cheekSquintRight"] ?? 0,
            noseSneerLeft: blendShapes["noseSneerLeft"] ?? 0,
            noseSneerRight: blendShapes["noseSneerRight"] ?? 0,
            tongueOut: blendShapes["tongueOut"] ?? 0
        )
    }
}

// MARK: - Codable Bounding Box

/// A Codable wrapper for CGRect to avoid extending CoreFoundation types
struct CodableBoundingBox: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
