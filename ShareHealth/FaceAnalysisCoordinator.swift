import UIKit
import Combine
import CoreMedia

/// Orchestrates Vision + ARKit analysis to produce complete facial metrics
class FaceAnalysisCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var currentStep = ""
    @Published var lastMetrics: FacialMetrics?
    @Published var analysisError: String?

    // MARK: - Private Properties

    private let visionAnalyzer = VisionFaceAnalyzer()
    private let arkitAnalyzer = ARKitFaceAnalyzer()

    // MARK: - Public Methods

    /// Analyze a captured face image and return complete metrics
    /// - Parameters:
    ///   - image: The captured UIImage
    ///   - completion: Callback with the analysis results
    func analyze(image: UIImage, completion: @escaping (FacialMetrics?) -> Void) {
        guard !isAnalyzing else {
            completion(nil)
            return
        }

        DispatchQueue.main.async {
            self.isAnalyzing = true
            self.analysisProgress = 0
            self.currentStep = "Starting analysis..."
            self.analysisError = nil
        }

        // Step 1: Vision analysis (always available)
        updateProgress(0.1, step: "Detecting face...")

        visionAnalyzer.analyze(image: image) { [weak self] visionMetrics in
            guard let self = self else { return }

            if visionMetrics == nil {
                self.completeAnalysis(with: nil, completion: completion)
                return
            }

            self.updateProgress(0.4, step: "Face detected")

            // Step 2: ARKit analysis (if available)
            if ARKitFaceAnalyzer.isAvailable {
                self.updateProgress(0.5, step: "Analyzing expressions...")

                self.arkitAnalyzer.analyze(image: image) { arkitMetrics in
                    self.updateProgress(0.8, step: "Calculating health indicators...")

                    let metrics = self.buildMetrics(
                        vision: visionMetrics,
                        arkit: arkitMetrics
                    )

                    self.completeAnalysis(with: metrics, completion: completion)
                }
            } else {
                // Vision-only mode
                self.updateProgress(0.8, step: "Calculating health indicators...")

                let metrics = self.buildMetrics(
                    vision: visionMetrics,
                    arkit: nil
                )

                self.completeAnalysis(with: metrics, completion: completion)
            }
        }
    }

    /// Analyze synchronously (blocking) - useful for testing
    func analyzeSync(image: UIImage) async -> FacialMetrics? {
        await withCheckedContinuation { continuation in
            analyze(image: image) { metrics in
                continuation.resume(returning: metrics)
            }
        }
    }

    // MARK: - Private Methods

    private func updateProgress(_ progress: Double, step: String) {
        DispatchQueue.main.async {
            self.analysisProgress = progress
            self.currentStep = step
        }
    }

    private func buildMetrics(vision: VisionFaceMetrics?, arkit: ARKitFaceMetrics?) -> FacialMetrics {
        let healthIndicators = HealthIndicatorCalculator.calculate(
            visionMetrics: vision,
            arkitMetrics: arkit
        )

        let analysisMode: AnalysisMode
        if vision != nil && arkit != nil {
            analysisMode = .visionAndARKit
        } else if vision != nil {
            analysisMode = .visionOnly
        } else {
            analysisMode = .none
        }

        return FacialMetrics(
            captureTimestamp: Date(),
            analysisMode: analysisMode,
            healthIndicators: healthIndicators,
            visionMetrics: vision,
            arkitMetrics: arkit
        )
    }

    private func completeAnalysis(with metrics: FacialMetrics?, completion: @escaping (FacialMetrics?) -> Void) {
        DispatchQueue.main.async {
            self.analysisProgress = 1.0
            self.currentStep = metrics != nil ? "Analysis complete" : "No face detected"
            self.lastMetrics = metrics
            self.isAnalyzing = false

            if metrics == nil {
                self.analysisError = "Could not detect a face in the image. Please ensure your face is clearly visible and well-lit."
            }

            completion(metrics)
        }
    }
}

// MARK: - JSON Export

extension FaceAnalysisCoordinator {

    /// Export metrics to JSON data
    static func exportToJSON(_ metrics: FacialMetrics) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(metrics)
        } catch {
            print("Failed to encode metrics to JSON: \(error)")
            return nil
        }
    }

    /// Save metrics to a JSON file
    static func saveMetrics(_ metrics: FacialMetrics, to url: URL) throws {
        guard let jsonData = exportToJSON(metrics) else {
            throw NSError(domain: "FaceAnalysis", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode metrics"
            ])
        }

        try jsonData.write(to: url)
    }

    /// Load metrics from a JSON file
    static func loadMetrics(from url: URL) throws -> FacialMetrics {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FacialMetrics.self, from: data)
    }
}

// MARK: - Real-time Analysis

extension FaceAnalysisCoordinator {

    /// Check if a face is detected in a sample buffer (for real-time overlay)
    func checkFacePresence(in sampleBuffer: CMSampleBuffer, completion: @escaping (Bool, Double) -> Void) {
        visionAnalyzer.analyzeRealtime(sampleBuffer: sampleBuffer, completion: completion)
    }
}
