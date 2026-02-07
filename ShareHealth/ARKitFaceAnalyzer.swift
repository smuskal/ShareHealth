import UIKit
import ARKit

/// Analyzes face images using ARKit to extract 52 blend shape coefficients
/// Only available on devices with TrueDepth camera (iPhone X and later)
class ARKitFaceAnalyzer: NSObject {

    private var arSession: ARSession?
    private var completion: ((ARKitFaceMetrics?) -> Void)?
    private var capturedImage: UIImage?
    private var isAnalyzing = false

    /// Check if ARKit face tracking is available on this device
    static var isAvailable: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    /// Analyze a captured image and extract ARKit blend shapes
    /// Note: ARKit requires a live camera session, so we use a brief capture
    /// - Parameters:
    ///   - image: The captured UIImage (used for context, actual analysis uses live camera)
    ///   - completion: Callback with extracted metrics or nil if not supported
    func analyze(image: UIImage, completion: @escaping (ARKitFaceMetrics?) -> Void) {
        guard Self.isAvailable else {
            print("ARKit face tracking not available on this device")
            completion(nil)
            return
        }

        guard !isAnalyzing else {
            print("ARKit analysis already in progress")
            completion(nil)
            return
        }

        isAnalyzing = true
        self.completion = completion
        self.capturedImage = image

        // Start ARKit session for brief face tracking
        startARSession()
    }

    private func startARSession() {
        arSession = ARSession()
        arSession?.delegate = self

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true

        arSession?.run(configuration, options: [.resetTracking])

        // Set a timeout - if no face detected in 3 seconds, return nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.isAnalyzing == true {
                self?.stopAnalysis(with: nil)
            }
        }
    }

    private func stopAnalysis(with metrics: ARKitFaceMetrics?) {
        arSession?.pause()
        arSession = nil
        isAnalyzing = false
        capturedImage = nil

        DispatchQueue.main.async { [weak self] in
            self?.completion?(metrics)
            self?.completion = nil
        }
    }

    /// Extract metrics from an ARFaceAnchor
    private func extractMetrics(from anchor: ARFaceAnchor) -> ARKitFaceMetrics {
        let blendShapes = anchor.blendShapes

        return ARKitFaceMetrics(
            // Eye expressions
            eyeBlinkLeft: blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0,
            eyeBlinkRight: blendShapes[.eyeBlinkRight]?.doubleValue ?? 0,
            eyeLookDownLeft: blendShapes[.eyeLookDownLeft]?.doubleValue ?? 0,
            eyeLookDownRight: blendShapes[.eyeLookDownRight]?.doubleValue ?? 0,
            eyeLookInLeft: blendShapes[.eyeLookInLeft]?.doubleValue ?? 0,
            eyeLookInRight: blendShapes[.eyeLookInRight]?.doubleValue ?? 0,
            eyeLookOutLeft: blendShapes[.eyeLookOutLeft]?.doubleValue ?? 0,
            eyeLookOutRight: blendShapes[.eyeLookOutRight]?.doubleValue ?? 0,
            eyeLookUpLeft: blendShapes[.eyeLookUpLeft]?.doubleValue ?? 0,
            eyeLookUpRight: blendShapes[.eyeLookUpRight]?.doubleValue ?? 0,
            eyeSquintLeft: blendShapes[.eyeSquintLeft]?.doubleValue ?? 0,
            eyeSquintRight: blendShapes[.eyeSquintRight]?.doubleValue ?? 0,
            eyeWideLeft: blendShapes[.eyeWideLeft]?.doubleValue ?? 0,
            eyeWideRight: blendShapes[.eyeWideRight]?.doubleValue ?? 0,

            // Eyebrow expressions
            browDownLeft: blendShapes[.browDownLeft]?.doubleValue ?? 0,
            browDownRight: blendShapes[.browDownRight]?.doubleValue ?? 0,
            browInnerUp: blendShapes[.browInnerUp]?.doubleValue ?? 0,
            browOuterUpLeft: blendShapes[.browOuterUpLeft]?.doubleValue ?? 0,
            browOuterUpRight: blendShapes[.browOuterUpRight]?.doubleValue ?? 0,

            // Jaw expressions
            jawForward: blendShapes[.jawForward]?.doubleValue ?? 0,
            jawLeft: blendShapes[.jawLeft]?.doubleValue ?? 0,
            jawRight: blendShapes[.jawRight]?.doubleValue ?? 0,
            jawOpen: blendShapes[.jawOpen]?.doubleValue ?? 0,

            // Mouth expressions
            mouthClose: blendShapes[.mouthClose]?.doubleValue ?? 0,
            mouthFunnel: blendShapes[.mouthFunnel]?.doubleValue ?? 0,
            mouthPucker: blendShapes[.mouthPucker]?.doubleValue ?? 0,
            mouthLeft: blendShapes[.mouthLeft]?.doubleValue ?? 0,
            mouthRight: blendShapes[.mouthRight]?.doubleValue ?? 0,
            mouthSmileLeft: blendShapes[.mouthSmileLeft]?.doubleValue ?? 0,
            mouthSmileRight: blendShapes[.mouthSmileRight]?.doubleValue ?? 0,
            mouthFrownLeft: blendShapes[.mouthFrownLeft]?.doubleValue ?? 0,
            mouthFrownRight: blendShapes[.mouthFrownRight]?.doubleValue ?? 0,
            mouthDimpleLeft: blendShapes[.mouthDimpleLeft]?.doubleValue ?? 0,
            mouthDimpleRight: blendShapes[.mouthDimpleRight]?.doubleValue ?? 0,
            mouthStretchLeft: blendShapes[.mouthStretchLeft]?.doubleValue ?? 0,
            mouthStretchRight: blendShapes[.mouthStretchRight]?.doubleValue ?? 0,
            mouthRollLower: blendShapes[.mouthRollLower]?.doubleValue ?? 0,
            mouthRollUpper: blendShapes[.mouthRollUpper]?.doubleValue ?? 0,
            mouthShrugLower: blendShapes[.mouthShrugLower]?.doubleValue ?? 0,
            mouthShrugUpper: blendShapes[.mouthShrugUpper]?.doubleValue ?? 0,
            mouthPressLeft: blendShapes[.mouthPressLeft]?.doubleValue ?? 0,
            mouthPressRight: blendShapes[.mouthPressRight]?.doubleValue ?? 0,
            mouthLowerDownLeft: blendShapes[.mouthLowerDownLeft]?.doubleValue ?? 0,
            mouthLowerDownRight: blendShapes[.mouthLowerDownRight]?.doubleValue ?? 0,
            mouthUpperUpLeft: blendShapes[.mouthUpperUpLeft]?.doubleValue ?? 0,
            mouthUpperUpRight: blendShapes[.mouthUpperUpRight]?.doubleValue ?? 0,

            // Cheek and nose
            cheekPuff: blendShapes[.cheekPuff]?.doubleValue ?? 0,
            cheekSquintLeft: blendShapes[.cheekSquintLeft]?.doubleValue ?? 0,
            cheekSquintRight: blendShapes[.cheekSquintRight]?.doubleValue ?? 0,
            noseSneerLeft: blendShapes[.noseSneerLeft]?.doubleValue ?? 0,
            noseSneerRight: blendShapes[.noseSneerRight]?.doubleValue ?? 0,

            // Tongue
            tongueOut: blendShapes[.tongueOut]?.doubleValue ?? 0
        )
    }
}

// MARK: - ARSessionDelegate

extension ARKitFaceAnalyzer: ARSessionDelegate {

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let faceAnchor = anchor as? ARFaceAnchor {
                let metrics = extractMetrics(from: faceAnchor)
                stopAnalysis(with: metrics)
                return
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Use updated anchor if we haven't captured yet
        guard isAnalyzing else { return }

        for anchor in anchors {
            if let faceAnchor = anchor as? ARFaceAnchor {
                let metrics = extractMetrics(from: faceAnchor)
                stopAnalysis(with: metrics)
                return
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARKit session failed: \(error.localizedDescription)")
        stopAnalysis(with: nil)
    }
}

// MARK: - Synchronous Analysis from Still Image

extension ARKitFaceAnalyzer {

    /// Analyze blend shapes from the most recent ARKit frame
    /// This is called internally after face tracking succeeds
    static func extractBlendShapesSync(from anchor: ARFaceAnchor) -> [String: Double] {
        let blendShapes = anchor.blendShapes
        var result: [String: Double] = [:]

        for (key, value) in blendShapes {
            result[key.rawValue] = value.doubleValue
        }

        return result
    }
}
