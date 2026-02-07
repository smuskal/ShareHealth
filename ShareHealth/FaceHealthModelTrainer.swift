import Foundation
import Accelerate

/// Trains and manages on-device models for face-to-health predictions
class FaceHealthModelTrainer {

    private let fileManager = FileManager.default

    private var modelsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("models", isDirectory: true)
    }

    init() {
        ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Training

    /// Train a model for the specified target (aggregates by day)
    func train(
        for targetId: String,
        captures: [StoredFaceCapture],
        completion: @escaping (Result<Double, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Group captures by date (day only, ignoring time)
                var dayGroups: [String: [(features: [Double], target: Double)]] = [:]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                for capture in captures {
                    guard let metrics = capture.metrics,
                          let healthData = capture.healthData else { continue }

                    guard let targetValue = self.extractTargetValue(targetId: targetId, healthData: healthData) else { continue }

                    let featureVector = self.extractFeatures(from: metrics)
                    let dayKey = dateFormatter.string(from: capture.captureDate)

                    if dayGroups[dayKey] == nil {
                        dayGroups[dayKey] = []
                    }
                    dayGroups[dayKey]?.append((features: featureVector, target: targetValue))
                }

                // Average features and targets per day
                var features: [[Double]] = []
                var targets: [Double] = []

                for (_, samples) in dayGroups {
                    guard !samples.isEmpty else { continue }

                    // Average features
                    let featureCount = samples[0].features.count
                    var avgFeatures = [Double](repeating: 0, count: featureCount)
                    for sample in samples {
                        for (i, f) in sample.features.enumerated() {
                            avgFeatures[i] += f
                        }
                    }
                    avgFeatures = avgFeatures.map { $0 / Double(samples.count) }

                    // Average target
                    let avgTarget = samples.map { $0.target }.reduce(0, +) / Double(samples.count)

                    features.append(avgFeatures)
                    targets.append(avgTarget)
                }

                guard features.count >= 7 else {
                    throw ModelTrainerError.insufficientData(required: 7, actual: features.count)
                }

                // Train linear regression model on all day-averaged data
                let model = try self.trainLinearRegression(features: features, targets: targets)

                // Calculate LOO-CV correlation by day (honest out-of-sample estimate)
                var looPredictions: [Double] = []
                for i in 0..<features.count {
                    var trainFeatures = features
                    var trainTargets = targets
                    trainFeatures.remove(at: i)
                    trainTargets.remove(at: i)

                    if let looModel = try? self.trainLinearRegression(features: trainFeatures, targets: trainTargets) {
                        looPredictions.append(self.predict(model: looModel, features: features[i]))
                    } else {
                        looPredictions.append(trainTargets.reduce(0, +) / Double(trainTargets.count))
                    }
                }
                let correlation = self.calculateCorrelation(actual: targets, predicted: looPredictions)

                // Save model (trained on all data, but correlation is LOO-CV)
                try self.saveModel(model, for: targetId, correlation: correlation)

                completion(.success(correlation))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Feature Extraction

    private func extractFeatures(from metrics: FacialMetrics) -> [Double] {
        let mp = metrics.mediapipeFeatures
        let hi = metrics.healthIndicators

        return [
            // MediaPipe features (normalized 0-1)
            mp.eyeOpennessLeft,
            mp.eyeOpennessRight,
            mp.eyeBlinkLeft,
            mp.eyeBlinkRight,
            mp.eyeSquintLeft,
            mp.eyeSquintRight,
            mp.browRaiseLeft,
            mp.browRaiseRight,
            mp.browFurrow,
            mp.smileLeft,
            mp.smileRight,
            mp.frownLeft,
            mp.frownRight,
            mp.mouthOpen,
            mp.lipPress,
            mp.cheekSquintLeft,
            mp.cheekSquintRight,

            // Health indicators (normalized to 0-1)
            hi.alertnessScore / 100.0,
            hi.tensionScore / 100.0,
            hi.smileScore / 100.0,
            hi.facialSymmetry / 100.0,

            // Head pose (normalized)
            (mp.headPitch + 45) / 90.0,  // Normalize -45 to 45 → 0 to 1
            (mp.headYaw + 45) / 90.0,
            (mp.headRoll + 45) / 90.0
        ]
    }

    func extractTargetValue(targetId: String, healthData: [String: String]) -> Double? {
        switch targetId {
        case "sleepScore":
            return SleepScoreCalculator.calculate(from: healthData)
        case "hrv":
            guard let value = healthData["Heart Rate Variability (ms)"],
                  let hrv = Double(value) else { return nil }
            return hrv
        case "restingHR":
            guard let value = healthData["Resting Heart Rate (count/min)"],
                  let rhr = Double(value) else { return nil }
            return rhr
        default:
            // For custom targets, the targetId is the health data key
            guard let value = healthData[targetId],
                  let numValue = Double(value) else { return nil }
            return numValue
        }
    }

    /// Check how many samples have data for a given target
    func sampleCountForTarget(_ targetId: String, captures: [StoredFaceCapture]) -> Int {
        var count = 0
        for capture in captures {
            guard let metrics = capture.metrics,
                  let healthData = capture.healthData else { continue }
            if extractTargetValue(targetId: targetId, healthData: healthData) != nil {
                count += 1
            }
        }
        return count
    }

    // MARK: - Linear Regression

    private func trainLinearRegression(features: [[Double]], targets: [Double]) throws -> LinearRegressionModel {
        let n = features.count
        let featureCount = features[0].count

        // Add bias term (column of 1s)
        var X = features.map { [1.0] + $0 }
        let y = targets

        // Normal equation: β = (X'X)^(-1) X'y
        // Using simplified approach for small datasets

        // Calculate X'X
        var XtX = [[Double]](repeating: [Double](repeating: 0, count: featureCount + 1), count: featureCount + 1)
        for i in 0..<(featureCount + 1) {
            for j in 0..<(featureCount + 1) {
                var sum = 0.0
                for k in 0..<n {
                    sum += X[k][i] * X[k][j]
                }
                XtX[i][j] = sum
            }
        }

        // Calculate X'y
        var Xty = [Double](repeating: 0, count: featureCount + 1)
        for i in 0..<(featureCount + 1) {
            var sum = 0.0
            for k in 0..<n {
                sum += X[k][i] * y[k]
            }
            Xty[i] = sum
        }

        // Solve using ridge regression (add small regularization for stability)
        let lambda = 0.01
        for i in 0..<(featureCount + 1) {
            XtX[i][i] += lambda
        }

        // Solve linear system using Gaussian elimination
        let coefficients = try solveLinearSystem(A: XtX, b: Xty)

        return LinearRegressionModel(
            coefficients: Array(coefficients.dropFirst()),
            bias: coefficients[0]
        )
    }

    private func solveLinearSystem(A: [[Double]], b: [Double]) throws -> [Double] {
        let n = b.count
        var augmented = A.enumerated().map { (i, row) in row + [b[i]] }

        // Forward elimination
        for i in 0..<n {
            // Find pivot
            var maxRow = i
            for k in (i+1)..<n {
                if abs(augmented[k][i]) > abs(augmented[maxRow][i]) {
                    maxRow = k
                }
            }
            augmented.swapAt(i, maxRow)

            if abs(augmented[i][i]) < 1e-10 {
                throw ModelTrainerError.singularMatrix
            }

            // Eliminate column
            for k in (i+1)..<n {
                let factor = augmented[k][i] / augmented[i][i]
                for j in i..<(n+1) {
                    augmented[k][j] -= factor * augmented[i][j]
                }
            }
        }

        // Back substitution
        var x = [Double](repeating: 0, count: n)
        for i in (0..<n).reversed() {
            x[i] = augmented[i][n]
            for j in (i+1)..<n {
                x[i] -= augmented[i][j] * x[j]
            }
            x[i] /= augmented[i][i]
        }

        return x
    }

    // MARK: - Sample Count

    /// Get the number of valid samples (days with both metrics and target data) for a target
    func getSampleCount(for targetId: String, captures: [StoredFaceCapture]) -> Int {
        var dayGroups: Set<String> = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for capture in captures {
            guard let metrics = capture.metrics,
                  let healthData = capture.healthData else { continue }

            guard extractTargetValue(targetId: targetId, healthData: healthData) != nil else { continue }

            let dayKey = dateFormatter.string(from: capture.captureDate)
            dayGroups.insert(dayKey)
        }

        return dayGroups.count
    }

    // MARK: - Prediction

    func predict(for targetId: String, metrics: FacialMetrics) -> Double? {
        guard let model = loadModel(for: targetId) else { return nil }
        let features = extractFeatures(from: metrics)
        return predict(model: model, features: features)
    }

    private func predict(model: LinearRegressionModel, features: [Double]) -> Double {
        var prediction = model.bias
        for (i, coef) in model.coefficients.enumerated() {
            if i < features.count {
                prediction += coef * features[i]
            }
        }
        return prediction
    }

    // MARK: - Correlation

    private func calculateCorrelation(actual: [Double], predicted: [Double]) -> Double {
        guard actual.count == predicted.count, actual.count > 1 else { return 0 }

        let n = Double(actual.count)
        let meanActual = actual.reduce(0, +) / n
        let meanPredicted = predicted.reduce(0, +) / n

        var numerator = 0.0
        var denomActual = 0.0
        var denomPredicted = 0.0

        for i in 0..<actual.count {
            let diffActual = actual[i] - meanActual
            let diffPredicted = predicted[i] - meanPredicted
            numerator += diffActual * diffPredicted
            denomActual += diffActual * diffActual
            denomPredicted += diffPredicted * diffPredicted
        }

        let denominator = sqrt(denomActual * denomPredicted)
        guard denominator > 0 else { return 0 }

        return numerator / denominator
    }

    // MARK: - Leave-One-Out Cross-Validation

    /// Performs leave-one-out cross-validation BY DAY and returns (R, actual values, predicted values)
    /// When multiple captures exist for the same day, they are all left out together to avoid data leakage.
    /// Features and targets are averaged per day.
    func leaveOneOutCV(
        for targetId: String,
        captures: [StoredFaceCapture]
    ) -> (correlation: Double, actuals: [Double], predictions: [Double], dates: [Date], captureIds: [[String]])? {
        // Group captures by date (day only, ignoring time)
        var dayGroups: [String: [(features: [Double], target: Double, captureId: String)]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for capture in captures {
            guard let metrics = capture.metrics,
                  let healthData = capture.healthData else { continue }

            guard let targetValue = extractTargetValue(targetId: targetId, healthData: healthData) else { continue }

            let featureVector = extractFeatures(from: metrics)
            let dayKey = dateFormatter.string(from: capture.captureDate)

            if dayGroups[dayKey] == nil {
                dayGroups[dayKey] = []
            }
            dayGroups[dayKey]?.append((features: featureVector, target: targetValue, captureId: capture.id))
        }

        // Average features and targets per day
        var dayData: [(dayKey: String, features: [Double], target: Double, date: Date, captureIds: [String])] = []

        for (dayKey, samples) in dayGroups {
            guard !samples.isEmpty else { continue }

            // Average features
            let featureCount = samples[0].features.count
            var avgFeatures = [Double](repeating: 0, count: featureCount)
            for sample in samples {
                for (i, f) in sample.features.enumerated() {
                    avgFeatures[i] += f
                }
            }
            avgFeatures = avgFeatures.map { $0 / Double(samples.count) }

            // Average target
            let avgTarget = samples.map { $0.target }.reduce(0, +) / Double(samples.count)

            // Get date from day key
            let date = dateFormatter.date(from: dayKey) ?? Date()

            // Collect capture IDs for this day
            let captureIds = samples.map { $0.captureId }

            dayData.append((dayKey: dayKey, features: avgFeatures, target: avgTarget, date: date, captureIds: captureIds))
        }

        // Sort by date
        dayData.sort { $0.date < $1.date }

        guard dayData.count >= 7 else { return nil }

        // Leave-one-DAY-out: for each day, train on other days, predict on that day
        var looPredictions: [Double] = []
        let allTargets = dayData.map { $0.target }
        let allFeatures = dayData.map { $0.features }

        for i in 0..<dayData.count {
            // Create training set excluding day i
            var trainFeatures = allFeatures
            var trainTargets = allTargets
            trainFeatures.remove(at: i)
            trainTargets.remove(at: i)

            // Train model on n-1 days
            guard let model = try? trainLinearRegression(features: trainFeatures, targets: trainTargets) else {
                // If training fails, use mean as prediction
                looPredictions.append(trainTargets.reduce(0, +) / Double(trainTargets.count))
                continue
            }

            // Predict on held-out day
            let prediction = predict(model: model, features: allFeatures[i])
            looPredictions.append(prediction)
        }

        // Calculate LOO-CV correlation
        let looCorrelation = calculateCorrelation(actual: allTargets, predicted: looPredictions)

        return (looCorrelation, allTargets, looPredictions, dayData.map { $0.date }, dayData.map { $0.captureIds })
    }

    /// Get detailed CV results for visualization
    func getCVResults(for targetId: String, captures: [StoredFaceCapture]) -> ModelCVResults? {
        guard let (correlation, actuals, predictions, dates, captureIds) = leaveOneOutCV(for: targetId, captures: captures) else {
            return nil
        }

        // Calculate additional statistics
        let n = actuals.count
        let meanActual = actuals.reduce(0, +) / Double(n)
        let errors = zip(actuals, predictions).map { $0 - $1 }
        let mae = errors.map { abs($0) }.reduce(0, +) / Double(n)
        let rmse = sqrt(errors.map { $0 * $0 }.reduce(0, +) / Double(n))

        return ModelCVResults(
            targetId: targetId,
            correlation: correlation,
            sampleCount: n,
            meanActual: meanActual,
            mae: mae,
            rmse: rmse,
            actuals: actuals,
            predictions: predictions,
            dates: dates,
            captureIds: captureIds
        )
    }

    // MARK: - Model Persistence

    func getModelCorrelation(for targetId: String) -> Double? {
        let metadataURL = modelsDirectory.appendingPathComponent("\(targetId)_metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ModelMetadata.self, from: data) else {
            return nil
        }
        return metadata.correlation
    }

    private func saveModel(_ model: LinearRegressionModel, for targetId: String, correlation: Double) throws {
        let modelURL = modelsDirectory.appendingPathComponent("\(targetId)_model.json")
        let metadataURL = modelsDirectory.appendingPathComponent("\(targetId)_metadata.json")

        let modelData = try JSONEncoder().encode(model)
        try modelData.write(to: modelURL)

        let metadata = ModelMetadata(
            targetId: targetId,
            correlation: correlation,
            trainedAt: Date(),
            featureCount: model.coefficients.count
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL)
    }

    private func loadModel(for targetId: String) -> LinearRegressionModel? {
        let modelURL = modelsDirectory.appendingPathComponent("\(targetId)_model.json")
        guard fileManager.fileExists(atPath: modelURL.path),
              let data = try? Data(contentsOf: modelURL),
              let model = try? JSONDecoder().decode(LinearRegressionModel.self, from: data) else {
            return nil
        }
        return model
    }

    /// Delete model for target
    func deleteModel(for targetId: String) {
        let modelURL = modelsDirectory.appendingPathComponent("\(targetId)_model.json")
        let metadataURL = modelsDirectory.appendingPathComponent("\(targetId)_metadata.json")
        try? fileManager.removeItem(at: modelURL)
        try? fileManager.removeItem(at: metadataURL)
    }

    /// Delete all models
    func deleteAllModels() {
        try? fileManager.removeItem(at: modelsDirectory)
        ensureDirectoryExists()
    }

    // MARK: - Model Snapshots (Save/Restore)

    private var snapshotsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("model_snapshots", isDirectory: true)
    }

    /// Get list of saved model snapshots
    func listSnapshots() -> [ModelSnapshot] {
        var snapshots: [ModelSnapshot] = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }

        for folder in contents {
            guard folder.hasDirectoryPath else { continue }
            let metadataURL = folder.appendingPathComponent("snapshot_metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(SnapshotMetadata.self, from: data) else { continue }

            snapshots.append(ModelSnapshot(
                id: folder.lastPathComponent,
                name: metadata.name,
                createdAt: metadata.createdAt,
                targetCount: metadata.targetIds.count,
                targetIds: metadata.targetIds
            ))
        }

        return snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    /// Save current models as a snapshot
    func saveSnapshot(name: String, targetIds: [String]) throws {
        // Create snapshots directory if needed
        if !fileManager.fileExists(atPath: snapshotsDirectory.path) {
            try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        }

        // Create snapshot folder with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let snapshotId = formatter.string(from: Date())
        let snapshotDir = snapshotsDirectory.appendingPathComponent(snapshotId)
        try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        // Copy model files for each target
        var savedTargets: [String] = []
        for targetId in targetIds {
            let modelURL = modelsDirectory.appendingPathComponent("\(targetId)_model.json")
            let metadataURL = modelsDirectory.appendingPathComponent("\(targetId)_metadata.json")

            if fileManager.fileExists(atPath: modelURL.path) {
                try fileManager.copyItem(
                    at: modelURL,
                    to: snapshotDir.appendingPathComponent("\(targetId)_model.json")
                )
            }
            if fileManager.fileExists(atPath: metadataURL.path) {
                try fileManager.copyItem(
                    at: metadataURL,
                    to: snapshotDir.appendingPathComponent("\(targetId)_metadata.json")
                )
                savedTargets.append(targetId)
            }
        }

        // Save snapshot metadata
        let metadata = SnapshotMetadata(
            name: name,
            createdAt: Date(),
            targetIds: savedTargets
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: snapshotDir.appendingPathComponent("snapshot_metadata.json"))
    }

    /// Restore models from a snapshot
    func restoreSnapshot(id: String) throws {
        let snapshotDir = snapshotsDirectory.appendingPathComponent(id)
        guard fileManager.fileExists(atPath: snapshotDir.path) else {
            throw ModelTrainerError.trainingFailed("Snapshot not found")
        }

        // Read snapshot metadata
        let metadataURL = snapshotDir.appendingPathComponent("snapshot_metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(SnapshotMetadata.self, from: data) else {
            throw ModelTrainerError.trainingFailed("Invalid snapshot metadata")
        }

        // Copy model files back to models directory
        for targetId in metadata.targetIds {
            let srcModel = snapshotDir.appendingPathComponent("\(targetId)_model.json")
            let srcMetadata = snapshotDir.appendingPathComponent("\(targetId)_metadata.json")
            let dstModel = modelsDirectory.appendingPathComponent("\(targetId)_model.json")
            let dstMetadata = modelsDirectory.appendingPathComponent("\(targetId)_metadata.json")

            // Remove existing files first
            try? fileManager.removeItem(at: dstModel)
            try? fileManager.removeItem(at: dstMetadata)

            if fileManager.fileExists(atPath: srcModel.path) {
                try fileManager.copyItem(at: srcModel, to: dstModel)
            }
            if fileManager.fileExists(atPath: srcMetadata.path) {
                try fileManager.copyItem(at: srcMetadata, to: dstMetadata)
            }
        }
    }

    /// Delete a snapshot
    func deleteSnapshot(id: String) {
        let snapshotDir = snapshotsDirectory.appendingPathComponent(id)
        try? fileManager.removeItem(at: snapshotDir)
    }

    /// Get feature importance for a trained model
    func getFeatureImportance(for targetId: String) -> [(name: String, coefficient: Double)]? {
        guard let model = loadModel(for: targetId) else { return nil }
        return model.featureImportance
    }
}

// MARK: - Data Models

struct LinearRegressionModel: Codable {
    let coefficients: [Double]
    let bias: Double

    /// Feature names in order
    static let featureNames: [String] = [
        "Eye Openness L", "Eye Openness R",
        "Eye Blink L", "Eye Blink R",
        "Eye Squint L", "Eye Squint R",
        "Brow Raise L", "Brow Raise R", "Brow Furrow",
        "Smile L", "Smile R",
        "Frown L", "Frown R",
        "Mouth Open", "Lip Press",
        "Cheek Squint L", "Cheek Squint R",
        "Alertness", "Tension", "Smile Score", "Symmetry",
        "Head Pitch", "Head Yaw", "Head Roll"
    ]

    /// Returns feature importance as (name, coefficient) pairs sorted by absolute magnitude
    var featureImportance: [(name: String, coefficient: Double)] {
        let pairs = zip(Self.featureNames, coefficients).map { ($0, $1) }
        return pairs.sorted { abs($0.1) > abs($1.1) }
    }
}

struct ModelMetadata: Codable {
    let targetId: String
    let correlation: Double
    let trainedAt: Date
    let featureCount: Int
    var isLOOCV: Bool = true  // Indicates if correlation is from LOO-CV
}

/// Results from leave-one-out cross-validation (by day)
struct ModelCVResults {
    let targetId: String
    let correlation: Double      // LOO-CV correlation (honest estimate)
    let sampleCount: Int         // Number of days (not individual captures)
    let meanActual: Double
    let mae: Double              // Mean Absolute Error
    let rmse: Double             // Root Mean Square Error
    let actuals: [Double]        // Actual values (daily averages)
    let predictions: [Double]    // LOO predictions (per day)
    let dates: [Date]            // Dates for each point (one per day)
    let captureIds: [[String]]   // Capture IDs for each day (for showing images when dot is tapped)
}

/// Metadata for a saved model snapshot
struct SnapshotMetadata: Codable {
    let name: String
    let createdAt: Date
    let targetIds: [String]
}

/// Represents a saved model snapshot
struct ModelSnapshot: Identifiable {
    let id: String
    let name: String
    let createdAt: Date
    let targetCount: Int
    let targetIds: [String]
}

// MARK: - Errors

enum ModelTrainerError: LocalizedError {
    case insufficientData(required: Int, actual: Int)
    case singularMatrix
    case trainingFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientData(let required, let actual):
            return "Need at least \(required) samples, have \(actual)"
        case .singularMatrix:
            return "Cannot solve - singular matrix"
        case .trainingFailed(let message):
            return "Training failed: \(message)"
        }
    }
}
