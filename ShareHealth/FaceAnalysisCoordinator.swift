import UIKit
import Combine
import CoreMedia

/// Orchestrates facial analysis using MediaPipe-compatible feature extraction
class FaceAnalysisCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var currentStep = ""
    @Published var lastMetrics: FacialMetrics?
    @Published var analysisError: String?

    // MARK: - Private Properties

    private let analyzer = MediaPipeFaceAnalyzer()

    // MARK: - Public Methods

    /// Analyze a captured face image and return MediaPipe-compatible metrics
    func analyze(image: UIImage, completion: @escaping (FacialMetrics?) -> Void) {
        guard !isAnalyzing else {
            completion(nil)
            return
        }

        DispatchQueue.main.async {
            self.isAnalyzing = true
            self.analysisProgress = 0
            self.currentStep = "Detecting face..."
            self.analysisError = nil
        }

        updateProgress(0.2, step: "Detecting face...")

        analyzer.analyze(image: image) { [weak self] metrics in
            guard let self = self else { return }

            if let metrics = metrics {
                self.updateProgress(0.8, step: "Computing health indicators...")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.completeAnalysis(with: metrics, completion: completion)
                }
            } else {
                self.completeAnalysis(with: nil, completion: completion)
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

    // MARK: - Real-time Detection

    /// Check if a face is detected in a sample buffer (for real-time overlay)
    func checkFacePresence(in sampleBuffer: CMSampleBuffer, completion: @escaping (Bool, Double) -> Void) {
        analyzer.detectFace(in: sampleBuffer, completion: completion)
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
