import Foundation
import Accelerate

// MARK: - Model Type

/// Available model types for face-to-health prediction
enum ModelType: String, Codable, CaseIterable {
    case linearRegression = "linear"
    case randomForest = "forest"

    var displayName: String {
        switch self {
        case .linearRegression: return "Linear Regression"
        case .randomForest: return "Random Forest"
        }
    }
}

// MARK: - Time of Day Category

/// Categorical time periods for face captures
enum TimeOfDayCategory: Int, Codable {
    case morning = 0    // 5:00 - 11:59
    case afternoon = 1  // 12:00 - 17:59
    case evening = 2    // 18:00 - 4:59

    static func from(date: Date) -> TimeOfDayCategory {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 5 && hour < 12 {
            return .morning
        } else if hour >= 12 && hour < 18 {
            return .afternoon
        } else {
            return .evening
        }
    }

    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    /// Returns one-hot encoding as [isMorning, isAfternoon] (evening is implicit 0,0)
    var oneHotEncoding: [Double] {
        switch self {
        case .morning: return [1.0, 0.0]
        case .afternoon: return [0.0, 1.0]
        case .evening: return [0.0, 0.0]
        }
    }
}

/// Trains and manages on-device models for face-to-health predictions
class FaceHealthModelTrainer {

    private let fileManager = FileManager.default

    /// Current model type preference (persisted via UserDefaults)
    static var currentModelType: ModelType {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "faceHealthModelType"),
               let type = ModelType(rawValue: rawValue) {
                return type
            }
            return .linearRegression
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "faceHealthModelType")
        }
    }

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

    /// Train a model using daily-aggregated data:
    /// - Features: averaged across all captures in a day
    /// - Target: from the LATEST capture of the day (for accumulating metrics)
    /// Uses leave-one-DAY-out cross-validation
    func train(
        for targetId: String,
        captures: [StoredFaceCapture],
        modelType: ModelType? = nil,
        completion: @escaping (Result<Double, Error>) -> Void
    ) {
        let useModelType = modelType ?? Self.currentModelType

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Aggregate data by day
                let dayData = self.aggregateByDay(captures: captures, targetId: targetId)

                guard dayData.count >= 7 else {
                    throw ModelTrainerError.insufficientData(required: 7, actual: dayData.count)
                }

                // Extract features and targets for training
                let allFeatures = dayData.map { $0.avgFeatures }
                let allTargets = dayData.map { $0.latestTarget }

                // Train final model on all data
                let model: TrainedModel
                switch useModelType {
                case .linearRegression:
                    let lrModel = try self.trainLinearRegression(features: allFeatures, targets: allTargets)
                    model = .linear(lrModel)
                case .randomForest:
                    let rfModel = self.trainRandomForest(features: allFeatures, targets: allTargets)
                    model = .forest(rfModel)
                }

                // Calculate LOO-CV correlation by DAY
                let sortedDays = dayData.sorted { $0.dayKey < $1.dayKey }
                var dayPredictions: [(actual: Double, predicted: Double)] = []

                for i in 0..<sortedDays.count {
                    // Training data: all days except current
                    var trainFeatures: [[Double]] = []
                    var trainTargets: [Double] = []
                    for j in 0..<sortedDays.count {
                        if j != i {
                            trainFeatures.append(sortedDays[j].avgFeatures)
                            trainTargets.append(sortedDays[j].latestTarget)
                        }
                    }

                    guard !trainFeatures.isEmpty else { continue }

                    // Train LOO model
                    let looModel: TrainedModel
                    switch useModelType {
                    case .linearRegression:
                        guard let lrModel = try? self.trainLinearRegression(features: trainFeatures, targets: trainTargets) else {
                            let meanPred = trainTargets.reduce(0, +) / Double(trainTargets.count)
                            dayPredictions.append((actual: sortedDays[i].latestTarget, predicted: meanPred))
                            continue
                        }
                        looModel = .linear(lrModel)
                    case .randomForest:
                        let rfModel = self.trainRandomForest(features: trainFeatures, targets: trainTargets)
                        looModel = .forest(rfModel)
                    }

                    // Predict on held-out day
                    let prediction = self.predict(model: looModel, features: sortedDays[i].avgFeatures)
                    dayPredictions.append((actual: sortedDays[i].latestTarget, predicted: prediction))
                }

                let actuals = dayPredictions.map { $0.actual }
                let predicted = dayPredictions.map { $0.predicted }
                let correlation = self.calculateCorrelation(actual: actuals, predicted: predicted)

                // Save model
                try self.saveModel(model, for: targetId, correlation: correlation, modelType: useModelType)

                completion(.success(correlation))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Aggregate captures by day: average features, use latest target
    private func aggregateByDay(captures: [StoredFaceCapture], targetId: String) -> [(dayKey: String, avgFeatures: [Double], latestTarget: Double, latestDate: Date, captureIds: [String])] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Group captures by day
        var dayGroups: [String: [(features: [Double], target: Double, date: Date, captureId: String)]] = [:]

        for capture in captures {
            guard let metrics = capture.metrics,
                  let healthData = capture.healthData else { continue }

            guard let targetValue = self.extractTargetValue(targetId: targetId, healthData: healthData) else { continue }

            let featureVector = self.extractFeatures(from: metrics, captureDate: capture.captureDate)
            let dayKey = dateFormatter.string(from: capture.captureDate)

            if dayGroups[dayKey] == nil {
                dayGroups[dayKey] = []
            }
            dayGroups[dayKey]?.append((features: featureVector, target: targetValue, date: capture.captureDate, captureId: capture.id))
        }

        // Aggregate each day
        var result: [(dayKey: String, avgFeatures: [Double], latestTarget: Double, latestDate: Date, captureIds: [String])] = []

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

            // Get latest capture's target (sorted by date, take last)
            let sortedSamples = samples.sorted { $0.date < $1.date }
            let latestTarget = sortedSamples.last!.target
            let latestDate = sortedSamples.last!.date
            let captureIds = sortedSamples.map { $0.captureId }

            result.append((dayKey: dayKey, avgFeatures: avgFeatures, latestTarget: latestTarget, latestDate: latestDate, captureIds: captureIds))
        }

        return result
    }

    // MARK: - Feature Extraction

    /// Extract features from facial metrics
    /// Note: Time-of-day features temporarily disabled for testing
    private func extractFeatures(from metrics: FacialMetrics, captureDate: Date) -> [Double] {
        let mp = metrics.mediapipeFeatures
        let hi = metrics.healthIndicators
        // let timeCategory = TimeOfDayCategory.from(date: captureDate)  // Disabled for testing

        let features = [
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

        // Time-of-day features disabled for testing
        // features.append(contentsOf: timeCategory.oneHotEncoding)

        return features
    }

    /// Extract features for prediction (uses current time)
    func extractFeaturesForPrediction(from metrics: FacialMetrics) -> [Double] {
        return extractFeatures(from: metrics, captureDate: Date())
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
            guard capture.metrics != nil,
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
        guard n > 0 else { throw ModelTrainerError.insufficientData(required: 1, actual: 0) }
        let featureCount = features[0].count

        // Add bias term (column of 1s)
        let X = features.map { [1.0] + $0 }
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

    // MARK: - Random Forest

    private func trainRandomForest(features: [[Double]], targets: [Double], numTrees: Int = 50, maxDepth: Int = 5) -> RandomForestModel {
        var trees: [DecisionTree] = []
        let n = features.count
        let featureCount = features[0].count

        // Track feature usage for importance
        var featureUsageCount = [Int](repeating: 0, count: featureCount)
        var featureImportanceSum = [Double](repeating: 0, count: featureCount)

        for _ in 0..<numTrees {
            // Bootstrap sample (sample with replacement)
            var sampleIndices: [Int] = []
            for _ in 0..<n {
                sampleIndices.append(Int.random(in: 0..<n))
            }

            let sampleFeatures = sampleIndices.map { features[$0] }
            let sampleTargets = sampleIndices.map { targets[$0] }

            // Build tree with feature importance tracking
            let (tree, importance) = buildDecisionTree(
                features: sampleFeatures,
                targets: sampleTargets,
                depth: 0,
                maxDepth: maxDepth,
                featureSubsetSize: Int(sqrt(Double(featureCount)))
            )
            trees.append(tree)

            // Accumulate feature importance
            for (idx, imp) in importance {
                featureUsageCount[idx] += 1
                featureImportanceSum[idx] += imp
            }
        }

        // Calculate normalized feature importance
        var featureImportance = [Double](repeating: 0, count: featureCount)
        for i in 0..<featureCount {
            if featureUsageCount[i] > 0 {
                featureImportance[i] = featureImportanceSum[i] / Double(featureUsageCount[i])
            }
        }

        // Normalize to sum to 1
        let totalImportance = featureImportance.reduce(0, +)
        if totalImportance > 0 {
            featureImportance = featureImportance.map { $0 / totalImportance }
        }

        return RandomForestModel(trees: trees, featureImportance: featureImportance)
    }

    private func buildDecisionTree(
        features: [[Double]],
        targets: [Double],
        depth: Int,
        maxDepth: Int,
        featureSubsetSize: Int
    ) -> (DecisionTree, [(Int, Double)]) {
        var importanceAccum: [(Int, Double)] = []

        // Base cases
        if depth >= maxDepth || features.count < 5 || Set(targets).count == 1 {
            let meanValue = targets.reduce(0, +) / Double(max(targets.count, 1))
            return (.leaf(meanValue), importanceAccum)
        }

        let featureCount = features[0].count

        // Randomly select feature subset
        var featureIndices = Array(0..<featureCount)
        featureIndices.shuffle()
        let selectedFeatures = Array(featureIndices.prefix(featureSubsetSize))

        // Find best split
        var bestFeature = 0
        var bestThreshold = 0.0
        var bestVarianceReduction = 0.0
        let totalVariance = calculateVariance(targets)

        for featureIdx in selectedFeatures {
            let values = features.map { $0[featureIdx] }
            let sortedValues = values.sorted()

            // Try a few threshold candidates
            let step = max(1, sortedValues.count / 10)
            for i in stride(from: step, to: sortedValues.count, by: step) {
                let threshold = (sortedValues[i-1] + sortedValues[i]) / 2

                var leftTargets: [Double] = []
                var rightTargets: [Double] = []

                for (j, feat) in features.enumerated() {
                    if feat[featureIdx] <= threshold {
                        leftTargets.append(targets[j])
                    } else {
                        rightTargets.append(targets[j])
                    }
                }

                if leftTargets.isEmpty || rightTargets.isEmpty { continue }

                let leftVariance = calculateVariance(leftTargets)
                let rightVariance = calculateVariance(rightTargets)
                let weightedVariance = (Double(leftTargets.count) * leftVariance + Double(rightTargets.count) * rightVariance) / Double(targets.count)
                let varianceReduction = totalVariance - weightedVariance

                if varianceReduction > bestVarianceReduction {
                    bestVarianceReduction = varianceReduction
                    bestFeature = featureIdx
                    bestThreshold = threshold
                }
            }
        }

        // If no good split found, return leaf
        if bestVarianceReduction <= 0 {
            let meanValue = targets.reduce(0, +) / Double(max(targets.count, 1))
            return (.leaf(meanValue), importanceAccum)
        }

        // Record feature importance
        importanceAccum.append((bestFeature, bestVarianceReduction))

        // Split data
        var leftFeatures: [[Double]] = []
        var leftTargets: [Double] = []
        var rightFeatures: [[Double]] = []
        var rightTargets: [Double] = []

        for (i, feat) in features.enumerated() {
            if feat[bestFeature] <= bestThreshold {
                leftFeatures.append(feat)
                leftTargets.append(targets[i])
            } else {
                rightFeatures.append(feat)
                rightTargets.append(targets[i])
            }
        }

        // Recursively build subtrees
        let (leftTree, leftImportance) = buildDecisionTree(
            features: leftFeatures,
            targets: leftTargets,
            depth: depth + 1,
            maxDepth: maxDepth,
            featureSubsetSize: featureSubsetSize
        )
        importanceAccum.append(contentsOf: leftImportance)

        let (rightTree, rightImportance) = buildDecisionTree(
            features: rightFeatures,
            targets: rightTargets,
            depth: depth + 1,
            maxDepth: maxDepth,
            featureSubsetSize: featureSubsetSize
        )
        importanceAccum.append(contentsOf: rightImportance)

        return (.split(featureIndex: bestFeature, threshold: bestThreshold, left: Box(leftTree), right: Box(rightTree)), importanceAccum)
    }

    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquaredDiff = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sumSquaredDiff / Double(values.count)
    }

    private func predictTree(_ tree: DecisionTree, features: [Double]) -> Double {
        switch tree {
        case .leaf(let value):
            return value
        case .split(let featureIndex, let threshold, let left, let right):
            // Bounds check to handle models trained with different feature counts
            guard featureIndex < features.count else {
                // If feature index is out of bounds, default to left branch
                return predictTree(left.value, features: features)
            }
            if features[featureIndex] <= threshold {
                return predictTree(left.value, features: features)
            } else {
                return predictTree(right.value, features: features)
            }
        }
    }

    private func predictForest(_ model: RandomForestModel, features: [Double]) -> Double {
        let predictions = model.trees.map { predictTree($0, features: features) }
        return predictions.reduce(0, +) / Double(predictions.count)
    }

    // MARK: - Sample Count

    /// Get the number of valid days (with both metrics and target data) for a target
    func getSampleCount(for targetId: String, captures: [StoredFaceCapture]) -> Int {
        var dayGroups: Set<String> = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for capture in captures {
            guard capture.metrics != nil,
                  let healthData = capture.healthData else { continue }

            guard extractTargetValue(targetId: targetId, healthData: healthData) != nil else { continue }

            let dayKey = dateFormatter.string(from: capture.captureDate)
            dayGroups.insert(dayKey)
        }

        return dayGroups.count
    }

    /// Get the number of individual captures with valid data for a target
    func getCaptureCount(for targetId: String, captures: [StoredFaceCapture]) -> Int {
        var count = 0
        for capture in captures {
            guard capture.metrics != nil,
                  let healthData = capture.healthData else { continue }

            guard extractTargetValue(targetId: targetId, healthData: healthData) != nil else { continue }

            count += 1
        }
        return count
    }

    // MARK: - Prediction

    func predict(for targetId: String, metrics: FacialMetrics) -> Double? {
        guard let (model, _) = loadModel(for: targetId) else { return nil }
        let features = extractFeaturesForPrediction(from: metrics)
        return predict(model: model, features: features)
    }

    private func predict(model: TrainedModel, features: [Double]) -> Double {
        switch model {
        case .linear(let lrModel):
            return predictLinear(lrModel, features: features)
        case .forest(let rfModel):
            return predictForest(rfModel, features: features)
        }
    }

    private func predictLinear(_ model: LinearRegressionModel, features: [Double]) -> Double {
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

    /// Performs leave-one-DAY-out cross-validation using daily-aggregated data.
    /// Features are averaged per day; target is from the latest capture of each day.
    func leaveOneOutCV(
        for targetId: String,
        captures: [StoredFaceCapture],
        modelType: ModelType? = nil
    ) -> (correlation: Double, actuals: [Double], predictions: [Double], dates: [Date], captureIds: [[String]])? {
        let useModelType = modelType ?? Self.currentModelType

        // Aggregate data by day
        let dayData = aggregateByDay(captures: captures, targetId: targetId)

        guard dayData.count >= 7 else { return nil }

        // Sort by day
        let sortedDays = dayData.sorted { $0.dayKey < $1.dayKey }

        var allActuals: [Double] = []
        var allPredictions: [Double] = []
        var allDates: [Date] = []
        var allCaptureIds: [[String]] = []

        for i in 0..<sortedDays.count {
            // Training data: all days except current
            var trainFeatures: [[Double]] = []
            var trainTargets: [Double] = []
            for j in 0..<sortedDays.count {
                if j != i {
                    trainFeatures.append(sortedDays[j].avgFeatures)
                    trainTargets.append(sortedDays[j].latestTarget)
                }
            }

            guard !trainFeatures.isEmpty else { continue }

            // Train LOO model
            let looModel: TrainedModel
            switch useModelType {
            case .linearRegression:
                guard let lrModel = try? self.trainLinearRegression(features: trainFeatures, targets: trainTargets) else {
                    let meanPred = trainTargets.reduce(0, +) / Double(trainTargets.count)
                    allActuals.append(sortedDays[i].latestTarget)
                    allPredictions.append(meanPred)
                    allDates.append(sortedDays[i].latestDate)
                    allCaptureIds.append(sortedDays[i].captureIds)
                    continue
                }
                looModel = .linear(lrModel)
            case .randomForest:
                let rfModel = self.trainRandomForest(features: trainFeatures, targets: trainTargets)
                looModel = .forest(rfModel)
            }

            // Predict on held-out day
            let prediction = self.predict(model: looModel, features: sortedDays[i].avgFeatures)

            allActuals.append(sortedDays[i].latestTarget)
            allPredictions.append(prediction)
            allDates.append(sortedDays[i].latestDate)
            allCaptureIds.append(sortedDays[i].captureIds)
        }

        let looCorrelation = calculateCorrelation(actual: allActuals, predicted: allPredictions)

        return (looCorrelation, allActuals, allPredictions, allDates, allCaptureIds)
    }

    /// Get detailed CV results for visualization
    func getCVResults(for targetId: String, captures: [StoredFaceCapture], modelType: ModelType? = nil) -> ModelCVResults? {
        guard let (correlation, actuals, predictions, dates, captureIds) = leaveOneOutCV(for: targetId, captures: captures, modelType: modelType) else {
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
        let safeId = sanitizeForFilename(targetId)
        let metadataURL = modelsDirectory.appendingPathComponent("\(safeId)_metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ModelMetadata.self, from: data) else {
            return nil
        }
        return metadata.correlation
    }

    func getModelType(for targetId: String) -> ModelType? {
        let safeId = sanitizeForFilename(targetId)
        let metadataURL = modelsDirectory.appendingPathComponent("\(safeId)_metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ModelMetadata.self, from: data) else {
            return nil
        }
        return metadata.modelType
    }

    /// Sanitize a target ID for use as a filename (remove special characters)
    private func sanitizeForFilename(_ targetId: String) -> String {
        // Replace problematic characters with underscores
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|()[]{}#%&")
        return targetId.components(separatedBy: invalidChars).joined(separator: "_")
    }

    private func saveModel(_ model: TrainedModel, for targetId: String, correlation: Double, modelType: ModelType) throws {
        let safeId = sanitizeForFilename(targetId)
        let modelURL = modelsDirectory.appendingPathComponent("\(safeId)_model.json")
        let metadataURL = modelsDirectory.appendingPathComponent("\(safeId)_metadata.json")

        let modelData = try JSONEncoder().encode(model)
        try modelData.write(to: modelURL)

        let metadata = ModelMetadata(
            targetId: targetId,
            correlation: correlation,
            trainedAt: Date(),
            featureCount: FeatureNames.all.count,
            modelType: modelType
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL)
    }

    private func loadModel(for targetId: String) -> (TrainedModel, ModelType)? {
        let safeId = sanitizeForFilename(targetId)
        let modelURL = modelsDirectory.appendingPathComponent("\(safeId)_model.json")
        guard fileManager.fileExists(atPath: modelURL.path),
              let data = try? Data(contentsOf: modelURL),
              let model = try? JSONDecoder().decode(TrainedModel.self, from: data) else {
            return nil
        }

        let modelType = getModelType(for: targetId) ?? .linearRegression
        return (model, modelType)
    }

    /// Delete model for target
    func deleteModel(for targetId: String) {
        let safeId = sanitizeForFilename(targetId)
        let modelURL = modelsDirectory.appendingPathComponent("\(safeId)_model.json")
        let metadataURL = modelsDirectory.appendingPathComponent("\(safeId)_metadata.json")
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
            let safeId = sanitizeForFilename(targetId)
            let modelURL = modelsDirectory.appendingPathComponent("\(safeId)_model.json")
            let metadataURL = modelsDirectory.appendingPathComponent("\(safeId)_metadata.json")

            if fileManager.fileExists(atPath: modelURL.path) {
                try fileManager.copyItem(
                    at: modelURL,
                    to: snapshotDir.appendingPathComponent("\(safeId)_model.json")
                )
            }
            if fileManager.fileExists(atPath: metadataURL.path) {
                try fileManager.copyItem(
                    at: metadataURL,
                    to: snapshotDir.appendingPathComponent("\(safeId)_metadata.json")
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
            let safeId = sanitizeForFilename(targetId)
            let srcModel = snapshotDir.appendingPathComponent("\(safeId)_model.json")
            let srcMetadata = snapshotDir.appendingPathComponent("\(safeId)_metadata.json")
            let dstModel = modelsDirectory.appendingPathComponent("\(safeId)_model.json")
            let dstMetadata = modelsDirectory.appendingPathComponent("\(safeId)_metadata.json")

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
    func getFeatureImportance(for targetId: String) -> [(name: String, importance: Double)]? {
        guard let (model, _) = loadModel(for: targetId) else { return nil }

        switch model {
        case .linear(let lrModel):
            // For linear regression, use absolute coefficient values (normalized)
            let absCoefs = lrModel.coefficients.map { abs($0) }
            let total = absCoefs.reduce(0, +)
            let normalized = total > 0 ? absCoefs.map { $0 / total } : absCoefs
            let pairs = zip(FeatureNames.all, normalized).map { ($0, $1) }
            return pairs.sorted { $0.1 > $1.1 }
        case .forest(let rfModel):
            let pairs = zip(FeatureNames.all, rfModel.featureImportance).map { ($0, $1) }
            return pairs.sorted { $0.1 > $1.1 }
        }
    }
}

// MARK: - Feature Names

struct FeatureNames {
    static let all: [String] = [
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
        // "Time: Morning", "Time: Afternoon"  // Disabled for testing
    ]
}

// MARK: - Trained Model (wrapper for both types)

enum TrainedModel: Codable {
    case linear(LinearRegressionModel)
    case forest(RandomForestModel)
}

// MARK: - Data Models

struct LinearRegressionModel: Codable {
    let coefficients: [Double]
    let bias: Double
}

struct RandomForestModel: Codable {
    let trees: [DecisionTree]
    let featureImportance: [Double]
}

/// Box wrapper for recursive enum
class Box<T: Codable>: Codable {
    let value: T
    init(_ value: T) { self.value = value }

    required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(T.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum DecisionTree: Codable {
    case leaf(Double)
    case split(featureIndex: Int, threshold: Double, left: Box<DecisionTree>, right: Box<DecisionTree>)
}

struct ModelMetadata: Codable {
    let targetId: String
    let correlation: Double
    let trainedAt: Date
    let featureCount: Int
    var modelType: ModelType = .linearRegression
    var isLOOCV: Bool = true  // Indicates if correlation is from LOO-CV
}

/// Results from leave-one-out cross-validation (daily aggregated)
struct ModelCVResults {
    let targetId: String
    let correlation: Double      // LOO-CV correlation (honest estimate)
    let sampleCount: Int         // Number of days
    let meanActual: Double
    let mae: Double              // Mean Absolute Error
    let rmse: Double             // Root Mean Square Error
    let actuals: [Double]        // Actual values (latest target per day)
    let predictions: [Double]    // LOO predictions (per day)
    let dates: [Date]            // Date for each day
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
            return "Need at least \(required) days of data, have \(actual)"
        case .singularMatrix:
            return "Cannot solve - singular matrix"
        case .trainingFailed(let message):
            return "Training failed: \(message)"
        }
    }
}
