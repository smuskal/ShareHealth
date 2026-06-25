import Foundation

enum HealthMetricStatistics {
    struct ErrorSummary {
        let meanActual: Double
        let mae: Double
        let rmse: Double
    }

    static func correlation(actual: [Double], predicted: [Double]) -> Double {
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

    static func errorSummary(actuals: [Double], predictions: [Double]) -> ErrorSummary? {
        guard actuals.count == predictions.count, !actuals.isEmpty else { return nil }

        let n = Double(actuals.count)
        let meanActual = actuals.reduce(0, +) / n
        let errors = zip(actuals, predictions).map { $0 - $1 }
        let mae = errors.map { abs($0) }.reduce(0, +) / n
        let rmse = sqrt(errors.map { $0 * $0 }.reduce(0, +) / n)

        return ErrorSummary(meanActual: meanActual, mae: mae, rmse: rmse)
    }
}
