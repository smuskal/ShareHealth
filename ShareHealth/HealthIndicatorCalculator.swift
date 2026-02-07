import Foundation

/// Calculates health-relevant indicators from raw facial metrics
struct HealthIndicatorCalculator {

    /// Calculate all health indicators from Vision and ARKit metrics
    /// - Parameters:
    ///   - visionMetrics: Metrics from Vision framework
    ///   - arkitMetrics: Metrics from ARKit (optional, nil on older devices)
    /// - Returns: Computed health indicators
    static func calculate(
        visionMetrics: VisionFaceMetrics?,
        arkitMetrics: ARKitFaceMetrics?
    ) -> FacialHealthIndicators {

        let alertness = calculateAlertness(vision: visionMetrics, arkit: arkitMetrics)
        let tension = calculateTension(vision: visionMetrics, arkit: arkitMetrics)
        let smile = calculateSmile(vision: visionMetrics, arkit: arkitMetrics)
        let symmetry = calculateSymmetry(vision: visionMetrics, arkit: arkitMetrics)
        let reliability = calculateReliability(vision: visionMetrics, arkit: arkitMetrics)

        return FacialHealthIndicators(
            alertnessScore: alertness,
            tensionScore: tension,
            smileScore: smile,
            facialSymmetry: symmetry,
            captureReliabilityScore: reliability
        )
    }

    // MARK: - Alertness Score (0-100)

    /// Calculate alertness based on eye openness, brow position, and head posture
    private static func calculateAlertness(
        vision: VisionFaceMetrics?,
        arkit: ARKitFaceMetrics?
    ) -> Double {
        var score = 50.0  // Default baseline
        var components = 0

        // Vision-based eye openness (primary signal)
        if let vision = vision {
            let eyeOpenness = vision.averageEyeOpenness * 100
            score = eyeOpenness
            components += 1

            // Penalize extreme head poses (tired people often tilt head)
            let posePenalty = (1.0 - vision.headPoseScore) * 20
            score -= posePenalty
        }

        // ARKit-based refinements
        if let arkit = arkit {
            // Eye wideness adds to alertness
            let wideBonus = arkit.averageEyeWide * 30

            // Blinking subtracts (frequent blinking = fatigue)
            let blinkPenalty = arkit.averageBlink * 20

            // Squinting subtracts
            let squintPenalty = arkit.averageSquint * 15

            // Raised brows indicate alertness
            let browBonus = arkit.browInnerUp * 15

            if components > 0 {
                // Combine with vision score
                score += wideBonus - blinkPenalty - squintPenalty + browBonus
            } else {
                // ARKit only mode
                let baseOpenness = (1.0 - arkit.averageBlink) * 70
                score = baseOpenness + wideBonus - squintPenalty + browBonus
            }
        }

        return clamp(score, min: 0, max: 100)
    }

    // MARK: - Tension Score (0-100)

    /// Calculate tension based on brow furrowing, jaw clenching, and facial tightness
    private static func calculateTension(
        vision: VisionFaceMetrics?,
        arkit: ARKitFaceMetrics?
    ) -> Double {
        var score = 20.0  // Low baseline (most people aren't tense)

        if let arkit = arkit {
            // Brow down = furrowed brows = tension
            let browTension = arkit.averageBrowDown * 40

            // Eye squint = concentration/tension
            let squintTension = arkit.averageSquint * 25

            // Jaw tension
            let jawTension = arkit.jawTension * 30

            // Mouth tension (pressed lips)
            let mouthTension = ((arkit.mouthPressLeft + arkit.mouthPressRight) / 2) * 20

            // Nose sneer can indicate stress
            let sneerTension = ((arkit.noseSneerLeft + arkit.noseSneerRight) / 2) * 15

            score = browTension + squintTension + jawTension + mouthTension + sneerTension
        } else if let vision = vision {
            // Vision-only: use head pose as proxy (tense people often have rigid posture)
            let poseRigidity = (1.0 - vision.headPoseScore) * 30

            // Lower eye openness can indicate squinting/tension
            let eyeTension = (1.0 - vision.averageEyeOpenness) * 25

            score = 15 + poseRigidity + eyeTension
        }

        return clamp(score, min: 0, max: 100)
    }

    // MARK: - Smile/Mood Score (0-100)

    /// Calculate smile/mood score based on mouth expressions
    private static func calculateSmile(
        vision: VisionFaceMetrics?,
        arkit: ARKitFaceMetrics?
    ) -> Double {
        var score = 50.0  // Neutral baseline

        if let arkit = arkit {
            // Smile intensity (primary signal)
            let smileIntensity = arkit.averageSmile * 100

            // Frown decreases score
            let frownPenalty = arkit.averageFrown * 60

            // Cheek raising (genuine smile)
            let cheekBonus = ((arkit.cheekSquintLeft + arkit.cheekSquintRight) / 2) * 20

            // Mouth corner position
            let mouthSideBonus = ((arkit.mouthDimpleLeft + arkit.mouthDimpleRight) / 2) * 15

            score = smileIntensity - frownPenalty + cheekBonus + mouthSideBonus

            // Ensure we start from neutral if no smile/frown detected
            if smileIntensity < 5 && frownPenalty < 5 {
                score = 50.0
            }
        } else if let vision = vision {
            // Vision-only: limited smile detection
            // Use eye openness as proxy (smiling eyes)
            let eyeSmile = vision.averageEyeOpenness * 30
            score = 40 + eyeSmile
        }

        return clamp(score, min: 0, max: 100)
    }

    // MARK: - Symmetry Score (0-100)

    /// Calculate facial symmetry across left/right features
    private static func calculateSymmetry(
        vision: VisionFaceMetrics?,
        arkit: ARKitFaceMetrics?
    ) -> Double {
        var score = 85.0  // Most faces are reasonably symmetric

        if let arkit = arkit {
            // Use ARKit's detailed symmetry calculation
            score = arkit.overallSymmetry * 100
        } else if let vision = vision {
            // Vision-only: use eye symmetry
            score = vision.eyeSymmetry * 100
        }

        return clamp(score, min: 0, max: 100)
    }

    // MARK: - Reliability Score (0-100)

    /// Calculate how reliable/trustworthy the metrics are based on capture quality
    private static func calculateReliability(
        vision: VisionFaceMetrics?,
        arkit: ARKitFaceMetrics?
    ) -> Double {
        var score = 0.0
        var factors = 0

        if let vision = vision {
            // Face detection confidence
            let confidenceScore = vision.faceQuality * 100
            score += confidenceScore
            factors += 1

            // Head pose - more centered = more reliable
            let poseScore = vision.headPoseScore * 100
            score += poseScore
            factors += 1

            // Face size in frame (larger = better quality)
            let faceSize = vision.faceBoundingBox.width * vision.faceBoundingBox.height
            let sizeScore = min(faceSize * 400, 100)  // Normalize: 0.25 of frame = 100%
            score += sizeScore
            factors += 1

            // Landmark count (more = better detection)
            let landmarkScore = min(Double(vision.landmarkCount) / 76.0 * 100, 100)
            score += landmarkScore
            factors += 1
        }

        if arkit != nil {
            // Having ARKit data is a reliability bonus
            score += 100
            factors += 1
        }

        if factors > 0 {
            score = score / Double(factors)
        }

        return clamp(score, min: 0, max: 100)
    }

    // MARK: - Utility

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

// MARK: - Score Interpretation

extension FacialHealthIndicators {

    /// Get a textual interpretation of the alertness score
    var alertnessDescription: String {
        switch alertnessScore {
        case 80...100: return "Very Alert"
        case 60..<80: return "Alert"
        case 40..<60: return "Moderate"
        case 20..<40: return "Tired"
        default: return "Fatigued"
        }
    }

    /// Get a textual interpretation of the tension score
    var tensionDescription: String {
        switch tensionScore {
        case 80...100: return "Very Tense"
        case 60..<80: return "Tense"
        case 40..<60: return "Moderate"
        case 20..<40: return "Relaxed"
        default: return "Very Relaxed"
        }
    }

    /// Get a textual interpretation of the smile score
    var moodDescription: String {
        switch smileScore {
        case 80...100: return "Very Happy"
        case 60..<80: return "Happy"
        case 40..<60: return "Neutral"
        case 20..<40: return "Unhappy"
        default: return "Very Unhappy"
        }
    }

    /// Get a textual interpretation of the symmetry score
    var symmetryDescription: String {
        switch facialSymmetry {
        case 90...100: return "Excellent"
        case 75..<90: return "Good"
        case 60..<75: return "Moderate"
        default: return "Asymmetric"
        }
    }

    /// Get a textual interpretation of the reliability score
    var reliabilityDescription: String {
        switch captureReliabilityScore {
        case 80...100: return "High Quality"
        case 60..<80: return "Good Quality"
        case 40..<60: return "Moderate Quality"
        default: return "Low Quality"
        }
    }
}
