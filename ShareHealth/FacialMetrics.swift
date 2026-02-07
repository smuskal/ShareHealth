import Foundation

// MARK: - Main Facial Metrics Container

/// Complete facial analysis results using MediaPipe
struct FacialMetrics: Codable {
    let captureTimestamp: Date
    let analysisVersion: String
    let analysisMode: AnalysisMode
    let mediapipeFeatures: MediaPipeFeatures
    let healthIndicators: FacialHealthIndicators
    let metadata: CaptureMetadata

    static let currentVersion = "1.0"

    init(
        captureTimestamp: Date = Date(),
        analysisMode: AnalysisMode = .mediapipe,
        mediapipeFeatures: MediaPipeFeatures,
        healthIndicators: FacialHealthIndicators,
        metadata: CaptureMetadata
    ) {
        self.captureTimestamp = captureTimestamp
        self.analysisVersion = Self.currentVersion
        self.analysisMode = analysisMode
        self.mediapipeFeatures = mediapipeFeatures
        self.healthIndicators = healthIndicators
        self.metadata = metadata
    }
}

// MARK: - Analysis Mode

enum AnalysisMode: String, Codable {
    case mediapipe = "mediapipe"
    case mediapipeBackfill = "mediapipeBackfill"
    case none = "none"
}

// MARK: - MediaPipe Features (22 features)

/// Features derived from MediaPipe Face Mesh 478 landmarks
struct MediaPipeFeatures: Codable {
    // Eye metrics (0-1 scale)
    let eyeBlinkLeft: Double
    let eyeBlinkRight: Double
    let eyeOpennessLeft: Double
    let eyeOpennessRight: Double
    let eyeSquintLeft: Double
    let eyeSquintRight: Double

    // Brow metrics (0-1 scale)
    let browRaiseLeft: Double
    let browRaiseRight: Double
    let browFurrow: Double

    // Mouth metrics (0-1 scale)
    let smileLeft: Double
    let smileRight: Double
    let frownLeft: Double
    let frownRight: Double
    let mouthOpen: Double
    let mouthPucker: Double
    let lipPress: Double

    // Jaw metrics (0-1 scale)
    let jawOpen: Double
    let jawLeft: Double
    let jawRight: Double

    // Cheek metrics (0-1 scale)
    let cheekSquintLeft: Double
    let cheekSquintRight: Double

    // Head pose (degrees)
    let headPitch: Double
    let headYaw: Double
    let headRoll: Double

    // MARK: - Computed Properties

    var averageEyeOpenness: Double {
        (eyeOpennessLeft + eyeOpennessRight) / 2.0
    }

    var averageEyeBlink: Double {
        (eyeBlinkLeft + eyeBlinkRight) / 2.0
    }

    var averageSmile: Double {
        (smileLeft + smileRight) / 2.0
    }

    var averageFrown: Double {
        (frownLeft + frownRight) / 2.0
    }

    var averageBrowRaise: Double {
        (browRaiseLeft + browRaiseRight) / 2.0
    }

    var eyeSymmetry: Double {
        1.0 - abs(eyeOpennessLeft - eyeOpennessRight)
    }

    var smileSymmetry: Double {
        1.0 - abs(smileLeft - smileRight)
    }

    var browSymmetry: Double {
        1.0 - abs(browRaiseLeft - browRaiseRight)
    }

    static let empty = MediaPipeFeatures(
        eyeBlinkLeft: 0, eyeBlinkRight: 0,
        eyeOpennessLeft: 0.5, eyeOpennessRight: 0.5,
        eyeSquintLeft: 0, eyeSquintRight: 0,
        browRaiseLeft: 0, browRaiseRight: 0,
        browFurrow: 0,
        smileLeft: 0, smileRight: 0,
        frownLeft: 0, frownRight: 0,
        mouthOpen: 0, mouthPucker: 0, lipPress: 0,
        jawOpen: 0, jawLeft: 0, jawRight: 0,
        cheekSquintLeft: 0, cheekSquintRight: 0,
        headPitch: 0, headYaw: 0, headRoll: 0
    )
}

// MARK: - Health Indicators (Computed Scores)

/// Derived health-relevant scores from facial analysis
struct FacialHealthIndicators: Codable {
    /// 0-100: Eye openness, brow position, head posture
    let alertnessScore: Double

    /// 0-100: Brow tension, squinting, lip press
    let tensionScore: Double

    /// 0-100: Smile intensity (50 = neutral, >50 = happy, <50 = unhappy)
    let smileScore: Double

    /// 0-100: Left/right balance across features
    let facialSymmetry: Double

    /// 0-100: Quality indicator for trusting metrics
    let captureReliabilityScore: Double

    /// Average of all scores weighted by reliability
    var overallScore: Double {
        let weights = [0.3, 0.2, 0.2, 0.15, 0.15]
        let invertedTension = 100.0 - tensionScore
        let scores = [alertnessScore, invertedTension, smileScore, facialSymmetry, captureReliabilityScore]
        return zip(weights, scores).map { $0 * $1 }.reduce(0, +)
    }

    static let empty = FacialHealthIndicators(
        alertnessScore: 0,
        tensionScore: 0,
        smileScore: 50,
        facialSymmetry: 0,
        captureReliabilityScore: 0
    )
}

// MARK: - Capture Metadata

struct CaptureMetadata: Codable {
    let imageWidth: Int
    let imageHeight: Int
    let faceWidth: Double
    let faceHeight: Double
    let landmarkCount: Int

    static let empty = CaptureMetadata(
        imageWidth: 0,
        imageHeight: 0,
        faceWidth: 0,
        faceHeight: 0,
        landmarkCount: 0
    )
}

// MARK: - Score Interpretation

extension FacialHealthIndicators {

    var alertnessDescription: String {
        switch alertnessScore {
        case 80...100: return "Very Alert"
        case 60..<80: return "Alert"
        case 40..<60: return "Moderate"
        case 20..<40: return "Tired"
        default: return "Fatigued"
        }
    }

    var tensionDescription: String {
        switch tensionScore {
        case 80...100: return "Very Tense"
        case 60..<80: return "Tense"
        case 40..<60: return "Moderate"
        case 20..<40: return "Relaxed"
        default: return "Very Relaxed"
        }
    }

    var moodDescription: String {
        switch smileScore {
        case 80...100: return "Very Happy"
        case 60..<80: return "Happy"
        case 40..<60: return "Neutral"
        case 20..<40: return "Unhappy"
        default: return "Very Unhappy"
        }
    }

    var symmetryDescription: String {
        switch facialSymmetry {
        case 90...100: return "Excellent"
        case 75..<90: return "Good"
        case 60..<75: return "Moderate"
        default: return "Asymmetric"
        }
    }

    var reliabilityDescription: String {
        switch captureReliabilityScore {
        case 80...100: return "High Quality"
        case 60..<80: return "Good Quality"
        case 40..<60: return "Moderate Quality"
        default: return "Low Quality"
        }
    }
}
