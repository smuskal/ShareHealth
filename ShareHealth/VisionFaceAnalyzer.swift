import UIKit
import Vision

/// Analyzes face images using Vision framework to extract landmarks, quality, and pose
class VisionFaceAnalyzer {

    /// Analyze a captured image and extract Vision-based face metrics
    /// - Parameters:
    ///   - image: The captured UIImage
    ///   - completion: Callback with extracted metrics or nil if no face detected
    func analyze(image: UIImage, completion: @escaping (VisionFaceMetrics?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let request = VNDetectFaceLandmarksRequest { request, error in
            if let error = error {
                print("Vision face detection error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let results = request.results as? [VNFaceObservation],
                  let face = results.first else {
                print("No face detected in image")
                completion(nil)
                return
            }

            let metrics = self.extractMetrics(from: face)
            completion(metrics)
        }

        // Configure for quality and capture quality
        request.revision = VNDetectFaceLandmarksRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: self.cgImageOrientation(from: image), options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform Vision request: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    /// Extract metrics from a VNFaceObservation
    private func extractMetrics(from face: VNFaceObservation) -> VisionFaceMetrics {
        // Face quality (confidence)
        let faceQuality = Double(face.confidence)

        // Head pose angles (in radians)
        let roll = face.roll?.doubleValue ?? 0
        let pitch = face.pitch?.doubleValue ?? 0
        let yaw = face.yaw?.doubleValue ?? 0

        // Eye openness from landmarks
        let (leftEyeOpenness, rightEyeOpenness) = calculateEyeOpenness(from: face.landmarks)

        // Count total landmarks
        let landmarkCount = countLandmarks(face.landmarks)

        return VisionFaceMetrics(
            faceQuality: faceQuality,
            roll: roll,
            pitch: pitch,
            yaw: yaw,
            leftEyeOpenness: leftEyeOpenness,
            rightEyeOpenness: rightEyeOpenness,
            faceBoundingBox: CodableBoundingBox(face.boundingBox),
            landmarkCount: landmarkCount
        )
    }

    /// Calculate eye openness from landmarks
    /// Returns a value from 0 (closed) to 1 (fully open)
    private func calculateEyeOpenness(from landmarks: VNFaceLandmarks2D?) -> (left: Double, right: Double) {
        guard let landmarks = landmarks else {
            return (0.5, 0.5)  // Default to half-open if no landmarks
        }

        let leftOpenness = calculateSingleEyeOpenness(
            eyeRegion: landmarks.leftEye,
            eyePupil: landmarks.leftPupil
        )

        let rightOpenness = calculateSingleEyeOpenness(
            eyeRegion: landmarks.rightEye,
            eyePupil: landmarks.rightPupil
        )

        return (leftOpenness, rightOpenness)
    }

    /// Calculate openness for a single eye based on vertical distance of eye contour
    private func calculateSingleEyeOpenness(eyeRegion: VNFaceLandmarkRegion2D?, eyePupil: VNFaceLandmarkRegion2D?) -> Double {
        guard let eyeRegion = eyeRegion,
              eyeRegion.pointCount >= 4 else {
            return 0.5
        }

        // Eye landmarks form an ellipse - calculate vertical span
        var yValues: [CGFloat] = []
        for i in 0..<eyeRegion.pointCount {
            yValues.append(eyeRegion.normalizedPoints[i].y)
        }
        guard let minY = yValues.min(), let maxY = yValues.max() else {
            return 0.5
        }

        let verticalSpan = maxY - minY

        // Normalize: typical eye opening ranges from 0.01 (closed) to 0.08 (wide open)
        // Map to 0-1 range
        let normalizedOpenness = min(max((verticalSpan - 0.01) / 0.07, 0), 1)

        return normalizedOpenness
    }

    /// Count total number of detected landmarks
    private func countLandmarks(_ landmarks: VNFaceLandmarks2D?) -> Int {
        guard let landmarks = landmarks else { return 0 }

        var count = 0

        if landmarks.allPoints != nil { count += landmarks.allPoints!.pointCount }

        return count
    }

    /// Convert UIImage orientation to CGImagePropertyOrientation
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

// MARK: - Real-time Analysis Extension

extension VisionFaceAnalyzer {

    /// Analyze a sample buffer for real-time face detection (used during capture preview)
    /// - Parameters:
    ///   - sampleBuffer: CMSampleBuffer from camera
    ///   - completion: Callback with face detection status and quality
    func analyzeRealtime(sampleBuffer: CMSampleBuffer, completion: @escaping (Bool, Double) -> Void) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(false, 0)
            return
        }

        let request = VNDetectFaceRectanglesRequest { request, error in
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
