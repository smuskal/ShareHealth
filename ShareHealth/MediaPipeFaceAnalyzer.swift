import UIKit
import Vision

/// Analyzes face images using Vision framework and computes MediaPipe-compatible features.
/// Uses the same feature computation algorithms as the Python backfill script for consistency.
///
/// Note: This uses Apple's Vision framework for landmark detection. For true MediaPipe,
/// add the MediaPipe iOS SDK as a package dependency. The feature computation logic
/// is identical regardless of the underlying landmark source.
class MediaPipeFaceAnalyzer {

    /// Analyze a captured image and extract MediaPipe-compatible features
    func analyze(image: UIImage, completion: @escaping (FacialMetrics?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let width = cgImage.width
        let height = cgImage.height

        // Create face landmarks request
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self = self else {
                completion(nil)
                return
            }

            if let error = error {
                print("Face detection error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let results = request.results as? [VNFaceObservation],
                  let face = results.first,
                  let landmarks = face.landmarks else {
                print("No face detected")
                completion(nil)
                return
            }

            // Extract features
            let metrics = self.computeMetrics(
                face: face,
                landmarks: landmarks,
                imageWidth: width,
                imageHeight: height
            )

            DispatchQueue.main.async {
                completion(metrics)
            }
        }

        request.revision = VNDetectFaceLandmarksRequestRevision3

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImageOrientation(from: image),
            options: [:]
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Vision request failed: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Feature Computation

    private func computeMetrics(
        face: VNFaceObservation,
        landmarks: VNFaceLandmarks2D,
        imageWidth: Int,
        imageHeight: Int
    ) -> FacialMetrics {

        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)

        // Get face bounding box in pixel coordinates
        let faceBox = face.boundingBox
        let faceWidth = faceBox.width * width
        let faceHeight = faceBox.height * height

        // Extract landmark points
        let leftEyePoints = extractPoints(from: landmarks.leftEye, in: faceBox, imageSize: CGSize(width: width, height: height))
        let rightEyePoints = extractPoints(from: landmarks.rightEye, in: faceBox, imageSize: CGSize(width: width, height: height))
        let leftEyebrowPoints = extractPoints(from: landmarks.leftEyebrow, in: faceBox, imageSize: CGSize(width: width, height: height))
        let rightEyebrowPoints = extractPoints(from: landmarks.rightEyebrow, in: faceBox, imageSize: CGSize(width: width, height: height))
        let outerLipsPoints = extractPoints(from: landmarks.outerLips, in: faceBox, imageSize: CGSize(width: width, height: height))
        let innerLipsPoints = extractPoints(from: landmarks.innerLips, in: faceBox, imageSize: CGSize(width: width, height: height))
        let nosePoints = extractPoints(from: landmarks.nose, in: faceBox, imageSize: CGSize(width: width, height: height))
        let faceContourPoints = extractPoints(from: landmarks.faceContour, in: faceBox, imageSize: CGSize(width: width, height: height))

        // Compute eye metrics
        let leftEyeOpenness = computeEyeOpenness(eyePoints: leftEyePoints)
        let rightEyeOpenness = computeEyeOpenness(eyePoints: rightEyePoints)
        let leftEyeBlink = 1.0 - leftEyeOpenness
        let rightEyeBlink = 1.0 - rightEyeOpenness
        let leftEyeSquint = computeEyeSquint(openness: leftEyeOpenness)
        let rightEyeSquint = computeEyeSquint(openness: rightEyeOpenness)

        // Compute brow metrics
        let leftBrowRaise = computeBrowRaise(browPoints: leftEyebrowPoints, eyePoints: leftEyePoints, faceHeight: faceHeight)
        let rightBrowRaise = computeBrowRaise(browPoints: rightEyebrowPoints, eyePoints: rightEyePoints, faceHeight: faceHeight)
        let browFurrow = computeBrowFurrow(leftBrow: leftEyebrowPoints, rightBrow: rightEyebrowPoints, faceWidth: faceWidth)

        // Compute mouth metrics
        let (smileLeft, smileRight) = computeSmile(outerLips: outerLipsPoints, faceHeight: faceHeight)
        let (frownLeft, frownRight) = computeFrown(outerLips: outerLipsPoints, faceHeight: faceHeight)
        let mouthOpen = computeMouthOpen(innerLips: innerLipsPoints, faceHeight: faceHeight)
        let mouthPucker = computeMouthPucker(outerLips: outerLipsPoints, faceWidth: faceWidth)
        let lipPress = computeLipPress(innerLips: innerLipsPoints, faceHeight: faceHeight)

        // Jaw metrics (approximated)
        let jawOpen = mouthOpen
        let (jawLeft, jawRight) = computeJawShift(faceContour: faceContourPoints, nose: nosePoints, faceWidth: faceWidth)

        // Cheek metrics (approximated from eye squint)
        let cheekSquintLeft = leftEyeSquint * 0.8
        let cheekSquintRight = rightEyeSquint * 0.8

        // Head pose
        let roll = (face.roll?.doubleValue ?? 0) * 180.0 / .pi
        let pitch = (face.pitch?.doubleValue ?? 0) * 180.0 / .pi
        let yaw = (face.yaw?.doubleValue ?? 0) * 180.0 / .pi

        // Create MediaPipe features
        let features = MediaPipeFeatures(
            eyeBlinkLeft: clamp(leftEyeBlink),
            eyeBlinkRight: clamp(rightEyeBlink),
            eyeOpennessLeft: clamp(leftEyeOpenness),
            eyeOpennessRight: clamp(rightEyeOpenness),
            eyeSquintLeft: clamp(leftEyeSquint),
            eyeSquintRight: clamp(rightEyeSquint),
            browRaiseLeft: clamp(leftBrowRaise),
            browRaiseRight: clamp(rightBrowRaise),
            browFurrow: clamp(browFurrow),
            smileLeft: clamp(smileLeft),
            smileRight: clamp(smileRight),
            frownLeft: clamp(frownLeft),
            frownRight: clamp(frownRight),
            mouthOpen: clamp(mouthOpen),
            mouthPucker: clamp(mouthPucker),
            lipPress: clamp(lipPress),
            jawOpen: clamp(jawOpen),
            jawLeft: clamp(jawLeft),
            jawRight: clamp(jawRight),
            cheekSquintLeft: clamp(cheekSquintLeft),
            cheekSquintRight: clamp(cheekSquintRight),
            headPitch: pitch,
            headYaw: yaw,
            headRoll: roll
        )

        // Compute health indicators
        let healthIndicators = computeHealthIndicators(features: features)

        // Compute capture quality
        let captureQuality = computeCaptureQuality(
            face: face,
            faceWidth: faceWidth,
            faceHeight: faceHeight,
            imageWidth: width,
            imageHeight: height
        )

        // Create metadata
        let metadata = CaptureMetadata(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            faceWidth: Double(faceWidth),
            faceHeight: Double(faceHeight),
            landmarkCount: landmarks.allPoints?.pointCount ?? 0
        )

        // Update health indicators with capture quality
        let finalHealthIndicators = FacialHealthIndicators(
            alertnessScore: healthIndicators.alertnessScore,
            tensionScore: healthIndicators.tensionScore,
            smileScore: healthIndicators.smileScore,
            facialSymmetry: healthIndicators.facialSymmetry,
            captureReliabilityScore: captureQuality * 100
        )

        return FacialMetrics(
            captureTimestamp: Date(),
            analysisMode: .mediapipe,
            mediapipeFeatures: features,
            healthIndicators: finalHealthIndicators,
            metadata: metadata
        )
    }

    // MARK: - Landmark Extraction

    private func extractPoints(from region: VNFaceLandmarkRegion2D?, in faceBox: CGRect, imageSize: CGSize) -> [CGPoint] {
        guard let region = region else { return [] }

        var points: [CGPoint] = []
        for i in 0..<region.pointCount {
            let normalizedPoint = region.normalizedPoints[i]
            // Convert from face-relative to image coordinates
            let x = (faceBox.origin.x + normalizedPoint.x * faceBox.width) * imageSize.width
            let y = (faceBox.origin.y + normalizedPoint.y * faceBox.height) * imageSize.height
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    // MARK: - Eye Metrics

    private func computeEyeOpenness(eyePoints: [CGPoint]) -> Double {
        guard eyePoints.count >= 6 else { return 0.5 }

        // Eye aspect ratio (EAR)
        let verticalDist1 = distance(eyePoints[1], eyePoints[5])
        let verticalDist2 = distance(eyePoints[2], eyePoints[4])
        let horizontalDist = distance(eyePoints[0], eyePoints[3])

        guard horizontalDist > 0 else { return 0.5 }

        let ear = (verticalDist1 + verticalDist2) / (2.0 * horizontalDist)

        // Normalize to 0-1 (typical EAR range is 0.1-0.4)
        return min(max((ear - 0.1) / 0.3, 0), 1)
    }

    private func computeEyeSquint(openness: Double) -> Double {
        // Squint is partial closure with tension
        if openness > 0.7 || openness < 0.3 {
            return 0
        }
        return 1.0 - abs(openness - 0.5) * 2
    }

    // MARK: - Brow Metrics

    private func computeBrowRaise(browPoints: [CGPoint], eyePoints: [CGPoint], faceHeight: CGFloat) -> Double {
        guard !browPoints.isEmpty, !eyePoints.isEmpty else { return 0 }

        let browCenterY = browPoints.map { $0.y }.reduce(0, +) / CGFloat(browPoints.count)
        let eyeTopY = eyePoints.map { $0.y }.min() ?? browCenterY

        // Distance from brow to eye top, normalized by face height
        let dist = eyeTopY - browCenterY  // Note: Y increases downward in image coords
        let normalized = dist / faceHeight

        // Map to 0-1
        return min(max((normalized - 0.02) / 0.06, 0), 1)
    }

    private func computeBrowFurrow(leftBrow: [CGPoint], rightBrow: [CGPoint], faceWidth: CGFloat) -> Double {
        guard !leftBrow.isEmpty, !rightBrow.isEmpty else { return 0 }

        // Find inner points of each brow
        let leftInnerX = leftBrow.map { $0.x }.max() ?? 0
        let rightInnerX = rightBrow.map { $0.x }.min() ?? 0

        let innerDist = rightInnerX - leftInnerX
        let normalized = innerDist / faceWidth

        // Smaller distance = more furrow
        return min(max((0.25 - normalized) / 0.1, 0), 1)
    }

    // MARK: - Mouth Metrics

    private func computeSmile(outerLips: [CGPoint], faceHeight: CGFloat) -> (Double, Double) {
        guard outerLips.count >= 12 else { return (0, 0) }

        // Get mouth corners and center
        let leftCorner = outerLips[0]
        let rightCorner = outerLips[6]
        let topCenter = outerLips[3]
        let bottomCenter = outerLips[9]
        let mouthCenterY = (topCenter.y + bottomCenter.y) / 2

        // Corner lift (negative = smile, since Y increases downward)
        let leftLift = (mouthCenterY - leftCorner.y) / faceHeight
        let rightLift = (mouthCenterY - rightCorner.y) / faceHeight

        let smileLeft = min(max(leftLift / 0.03, 0), 1)
        let smileRight = min(max(rightLift / 0.03, 0), 1)

        return (smileLeft, smileRight)
    }

    private func computeFrown(outerLips: [CGPoint], faceHeight: CGFloat) -> (Double, Double) {
        guard outerLips.count >= 12 else { return (0, 0) }

        let leftCorner = outerLips[0]
        let rightCorner = outerLips[6]
        let topCenter = outerLips[3]
        let bottomCenter = outerLips[9]
        let mouthCenterY = (topCenter.y + bottomCenter.y) / 2

        // Corner drop (positive = frown)
        let leftDrop = (leftCorner.y - mouthCenterY) / faceHeight
        let rightDrop = (rightCorner.y - mouthCenterY) / faceHeight

        let frownLeft = min(max(leftDrop / 0.02, 0), 1)
        let frownRight = min(max(rightDrop / 0.02, 0), 1)

        return (frownLeft, frownRight)
    }

    private func computeMouthOpen(innerLips: [CGPoint], faceHeight: CGFloat) -> Double {
        guard innerLips.count >= 6 else { return 0 }

        let topCenter = innerLips[0]
        let bottomCenter = innerLips[3]

        let lipDist = distance(topCenter, bottomCenter)
        let normalized = lipDist / faceHeight

        // Map to 0-1
        return min(max((normalized - 0.01) / 0.1, 0), 1)
    }

    private func computeMouthPucker(outerLips: [CGPoint], faceWidth: CGFloat) -> Double {
        guard outerLips.count >= 12 else { return 0 }

        let leftCorner = outerLips[0]
        let rightCorner = outerLips[6]

        let mouthWidth = distance(leftCorner, rightCorner)
        let normalized = mouthWidth / faceWidth

        // Smaller = more pucker
        return min(max((0.4 - normalized) / 0.15, 0), 1)
    }

    private func computeLipPress(innerLips: [CGPoint], faceHeight: CGFloat) -> Double {
        guard innerLips.count >= 6 else { return 0 }

        let topCenter = innerLips[0]
        let bottomCenter = innerLips[3]

        let lipDist = distance(topCenter, bottomCenter)
        let normalized = lipDist / faceHeight

        // Very small distance = pressed
        return min(max((0.015 - normalized) / 0.01, 0), 1)
    }

    // MARK: - Jaw Metrics

    private func computeJawShift(faceContour: [CGPoint], nose: [CGPoint], faceWidth: CGFloat) -> (Double, Double) {
        guard !faceContour.isEmpty, !nose.isEmpty else { return (0, 0) }

        // Find chin (bottom of face contour)
        let chin = faceContour.min(by: { $0.y > $1.y }) ?? faceContour[0]
        let noseCenter = CGPoint(
            x: nose.map { $0.x }.reduce(0, +) / CGFloat(nose.count),
            y: nose.map { $0.y }.reduce(0, +) / CGFloat(nose.count)
        )

        let offset = (chin.x - noseCenter.x) / faceWidth

        let jawLeft = offset < 0 ? min(max(-offset / 0.05, 0), 1) : 0
        let jawRight = offset > 0 ? min(max(offset / 0.05, 0), 1) : 0

        return (jawLeft, jawRight)
    }

    // MARK: - Health Indicators

    private func computeHealthIndicators(features: MediaPipeFeatures) -> FacialHealthIndicators {
        // Alertness
        let eyeOpenness = features.averageEyeOpenness * 100
        let browLift = features.averageBrowRaise * 20
        let posePenalty = max(0, -features.headPitch) * 0.5
        let alertness = min(max(eyeOpenness + browLift - posePenalty, 0), 100)

        // Tension
        let browTension = features.browFurrow * 40
        let eyeTension = (features.eyeSquintLeft + features.eyeSquintRight) / 2 * 25
        let mouthTension = features.lipPress * 20
        let jawTension = (1.0 - features.jawOpen) * 15
        let tension = min(max(browTension + eyeTension + mouthTension + jawTension, 0), 100)

        // Smile score
        let smileIntensity = features.averageSmile * 100
        let frownIntensity = features.averageFrown * 60
        let cheekBonus = (features.cheekSquintLeft + features.cheekSquintRight) / 2 * 20
        let smileScore = min(max(50 + (smileIntensity + cheekBonus - frownIntensity) / 2, 0), 100)

        // Symmetry
        let symmetry = (features.eyeSymmetry + features.smileSymmetry + features.browSymmetry) / 3 * 100

        return FacialHealthIndicators(
            alertnessScore: alertness,
            tensionScore: tension,
            smileScore: smileScore,
            facialSymmetry: symmetry,
            captureReliabilityScore: 0  // Will be set separately
        )
    }

    private func computeCaptureQuality(
        face: VNFaceObservation,
        faceWidth: CGFloat,
        faceHeight: CGFloat,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> Double {
        // Size score
        let faceArea = faceWidth * faceHeight
        let imageArea = imageWidth * imageHeight
        let sizeScore = min((faceArea / imageArea) * 10, 1.0)

        // Position score (centered = better)
        let faceCenterX = face.boundingBox.midX
        let faceCenterY = face.boundingBox.midY
        let offsetX = abs(faceCenterX - 0.5) * 2
        let offsetY = abs(faceCenterY - 0.5) * 2
        let positionScore = 1.0 - (offsetX + offsetY) / 2

        // Confidence score
        let confidenceScore = Double(face.confidence)

        return (sizeScore + positionScore + confidenceScore) / 3
    }

    // MARK: - Utilities

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }

    private func clamp(_ value: Double, min: Double = 0, max: Double = 1) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    private func cgImageOrientation(from image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Real-time Analysis

extension MediaPipeFaceAnalyzer {

    /// Quick face detection for real-time preview
    func detectFace(in sampleBuffer: CMSampleBuffer, completion: @escaping (Bool, Double) -> Void) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(false, 0)
            return
        }

        let request = VNDetectFaceRectanglesRequest { request, _ in
            DispatchQueue.main.async {
                if let results = request.results as? [VNFaceObservation],
                   let face = results.first {
                    completion(true, Double(face.confidence))
                } else {
                    completion(false, 0)
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])

        DispatchQueue.global(qos: .userInteractive).async {
            try? handler.perform([request])
        }
    }
}
