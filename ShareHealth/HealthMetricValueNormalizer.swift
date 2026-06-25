import Foundation

enum HealthMetricValueNormalizer {
    struct Profile {
        let min: Double
        let max: Double
        let typical: Double
        let correctionFactors: [Double]
        let supportsLowUnitConversion: Bool

        func contains(_ value: Double) -> Bool {
            value >= min && value <= max
        }
    }

    struct PairedSeriesResult {
        let actuals: [Double]
        let predictions: [Double]
        let keptIndices: [Int]
        let correctedActualCount: Int
        let correctedPredictionCount: Int
        let droppedCount: Int

        var changed: Bool {
            correctedActualCount > 0 || correctedPredictionCount > 0 || droppedCount > 0
        }
    }

    static func profile(for targetId: String) -> Profile? {
        let normalizedId = HealthMetricTargetAliases.canonicalDisplayTargetId(targetId).lowercased()

        if normalizedId.contains("lean body") && normalizedId.contains("(lb)") {
            return Profile(
                min: 80,
                max: 350,
                typical: 135,
                correctionFactors: poundMassCorrectionFactors,
                supportsLowUnitConversion: true
            )
        }

        if normalizedId.contains("weight") && normalizedId.contains("(lb)") {
            return Profile(
                min: 50,
                max: 700,
                typical: 170,
                correctionFactors: poundMassCorrectionFactors,
                supportsLowUnitConversion: true
            )
        }

        if normalizedId.contains("(lb)") {
            return Profile(
                min: 30,
                max: 700,
                typical: 150,
                correctionFactors: poundMassCorrectionFactors,
                supportsLowUnitConversion: true
            )
        }

        if normalizedId.contains("(kg)") {
            return Profile(
                min: 15,
                max: 300,
                typical: 70,
                correctionFactors: metricMassCorrectionFactors,
                supportsLowUnitConversion: true
            )
        }

        if normalizedId.contains("(%)") {
            return Profile(
                min: 0,
                max: 100,
                typical: 50,
                correctionFactors: percentageCorrectionFactors,
                supportsLowUnitConversion: false
            )
        }

        return nil
    }

    static func referenceValue(for values: [Double], targetId: String) -> Double? {
        guard let profile = profile(for: targetId) else { return nil }

        let plausibleValues = values
            .filter { $0.isFinite && profile.contains($0) }
            .sorted()

        if plausibleValues.count >= 3 {
            return median(ofSortedValues: plausibleValues)
        }

        let correctedValues = values
            .compactMap { normalizedValue($0, targetId: targetId, reference: profile.typical) }
            .filter { profile.contains($0) }
            .sorted()

        guard !correctedValues.isEmpty else {
            return profile.typical
        }

        return median(ofSortedValues: correctedValues)
    }

    static func normalizedValue(_ value: Double, targetId: String, reference: Double? = nil) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        guard let profile = profile(for: targetId) else { return value }
        let anchor = reference.flatMap { profile.contains($0) ? $0 : nil } ?? profile.typical

        if profile.contains(value) {
            guard profile.supportsLowUnitConversion else { return value }

            let candidates = profile.correctionFactors.compactMap { factor -> Double? in
                guard factor > 1 else { return nil }
                let corrected = value * factor
                return profile.contains(corrected) ? corrected : nil
            }

            guard let bestCandidate = candidates.min(by: {
                score($0, reference: anchor, profile: profile) < score($1, reference: anchor, profile: profile)
            }) else {
                return value
            }

            let currentScore = score(value, reference: anchor, profile: profile)
            let candidateScore = score(bestCandidate, reference: anchor, profile: profile)
            return candidateScore + 0.05 < currentScore ? bestCandidate : value
        }

        let candidates: [Double]
        if value > profile.max {
            candidates = profile.correctionFactors.compactMap { factor -> Double? in
                guard factor > 1 else { return nil }
                let corrected = value / factor
                return profile.contains(corrected) ? corrected : nil
            }
        } else if profile.supportsLowUnitConversion {
            candidates = profile.correctionFactors.compactMap { factor -> Double? in
                guard factor > 1 else { return nil }
                let corrected = value * factor
                return profile.contains(corrected) ? corrected : nil
            }
        } else {
            candidates = []
        }

        return candidates.min { lhs, rhs in
            score(lhs, reference: anchor, profile: profile) < score(rhs, reference: anchor, profile: profile)
        }
    }

    static func normalizeHealthData(_ healthData: [String: String], context: String? = nil) -> [String: String] {
        var normalizedData = healthData
        var corrections: [String] = []

        for (key, stringValue) in healthData {
            guard let rawValue = Double(stringValue) else { continue }

            let canonicalKey = HealthMetricTargetAliases.canonicalDisplayTargetId(key)
            guard profile(for: canonicalKey) != nil else { continue }

            guard let fixedValue = normalizedValue(rawValue, targetId: canonicalKey) else {
                normalizedData.removeValue(forKey: key)
                corrections.append("\(key)=\(stringValue) removed")
                continue
            }

            let valueChanged = !approximatelyEqual(rawValue, fixedValue)
            let keyChanged = canonicalKey != key
            guard valueChanged || keyChanged else { continue }

            if keyChanged {
                normalizedData.removeValue(forKey: key)
            }
            normalizedData[canonicalKey] = formatStorageValue(fixedValue)

            let destination = keyChanged ? "\(key) -> \(canonicalKey)" : key
            corrections.append("\(destination) \(stringValue) -> \(normalizedData[canonicalKey] ?? "")")
        }

        if let context, !corrections.isEmpty {
            print("ShareHealthMetricDebug health data unit normalization [\(context)]: \(corrections.joined(separator: "; "))")
        }

        return normalizedData
    }

    static func normalizePairedSeries(actuals: [Double], predictions: [Double], targetId: String) -> PairedSeriesResult {
        guard profile(for: targetId) != nil else {
            let count = min(actuals.count, predictions.count)
            return PairedSeriesResult(
                actuals: Array(actuals.prefix(count)),
                predictions: Array(predictions.prefix(count)),
                keptIndices: Array(0..<count),
                correctedActualCount: 0,
                correctedPredictionCount: 0,
                droppedCount: abs(actuals.count - predictions.count)
            )
        }

        let reference = referenceValue(for: actuals, targetId: targetId)
        var normalizedActuals: [Double] = []
        var normalizedPredictions: [Double] = []
        var keptIndices: [Int] = []
        var correctedActualCount = 0
        var correctedPredictionCount = 0
        var droppedCount = 0

        for index in 0..<min(actuals.count, predictions.count) {
            let rawActual = actuals[index]
            let rawPrediction = predictions[index]

            guard let actual = normalizedValue(rawActual, targetId: targetId, reference: reference) else {
                droppedCount += 1
                continue
            }

            guard let prediction = normalizedValue(rawPrediction, targetId: targetId, reference: reference) else {
                droppedCount += 1
                continue
            }

            if !approximatelyEqual(rawActual, actual) {
                correctedActualCount += 1
            }
            if prediction.isFinite && !approximatelyEqual(rawPrediction, prediction) {
                correctedPredictionCount += 1
            }

            normalizedActuals.append(actual)
            normalizedPredictions.append(prediction)
            keptIndices.append(index)
        }

        droppedCount += max(0, actuals.count - predictions.count)

        return PairedSeriesResult(
            actuals: normalizedActuals,
            predictions: normalizedPredictions,
            keptIndices: keptIndices,
            correctedActualCount: correctedActualCount,
            correctedPredictionCount: correctedPredictionCount,
            droppedCount: droppedCount
        )
    }

    private static let poundMassCorrectionFactors: [Double] = [
        2.2046226218,
        4.5359237,
        10.0,
        22.0462262,
        45.359237,
        50.0,
        60.0,
        70.0,
        75.0,
        80.0,
        90.0,
        100.0,
        453.59237,
        1000.0,
        10000.0
    ]

    private static let metricMassCorrectionFactors: [Double] = [
        10.0,
        100.0,
        1000.0
    ]

    private static let percentageCorrectionFactors: [Double] = [
        100.0
    ]

    private static func score(_ value: Double, reference: Double, profile: Profile) -> Double {
        let referenceDistance = abs(value - reference) / max(reference, 1)
        let lowerEdgePenalty = value < profile.min * 1.15 ? 0.20 : 0
        let upperEdgePenalty = value > profile.max * 0.90 ? 0.20 : 0
        return referenceDistance + lowerEdgePenalty + upperEdgePenalty
    }

    private static func median(ofSortedValues values: [Double]) -> Double {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(0.000001, abs(lhs) * 0.000001)
    }

    private static func formatStorageValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}
