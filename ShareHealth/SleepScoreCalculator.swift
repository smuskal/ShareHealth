import Foundation

/// Calculates Oura-inspired sleep score (0-100) matching AI Steve's formula
struct SleepScoreCalculator {

    // MARK: - Component Weights

    private static let durationWeight: Double = 40.0
    private static let deepSleepWeight: Double = 20.0
    private static let remSleepWeight: Double = 20.0
    private static let efficiencyWeight: Double = 20.0

    // MARK: - Targets

    private static let durationTarget: Double = 7.5   // hours
    private static let deepSleepTarget: Double = 1.5  // hours
    private static let remSleepTarget: Double = 1.75  // hours

    // MARK: - Calculate Sleep Score

    /// Calculate sleep score from health data dictionary
    /// - Parameter healthData: Dictionary with keys like "Sleep Analysis [Total] (hr)"
    /// - Returns: Sleep score 0-100, or nil if insufficient data
    static func calculate(from healthData: [String: String]) -> Double? {
        // Extract sleep metrics
        guard let totalSleep = extractDouble(healthData, key: "Sleep Analysis [Total] (hr)"),
              totalSleep > 0 else {
            return nil
        }

        let deepSleep = extractDouble(healthData, key: "Sleep Analysis [Deep] (hr)") ?? 0
        let remSleep = extractDouble(healthData, key: "Sleep Analysis [REM] (hr)") ?? 0
        let inBed = extractDouble(healthData, key: "Sleep Analysis [In Bed] (hr)") ?? 0

        return calculate(
            totalSleep: totalSleep,
            deepSleep: deepSleep,
            remSleep: remSleep,
            timeInBed: inBed
        )
    }

    /// Calculate sleep score from individual components
    static func calculate(
        totalSleep: Double,
        deepSleep: Double,
        remSleep: Double,
        timeInBed: Double
    ) -> Double {
        // Duration score (40 pts max) - target 7.5 hours
        let durationScore = min((totalSleep / durationTarget) * durationWeight, durationWeight)

        // Deep sleep score (20 pts max) - target 1.5 hours
        let deepScore = min((deepSleep / deepSleepTarget) * deepSleepWeight, deepSleepWeight)

        // REM sleep score (20 pts max) - target 1.75 hours
        let remScore = min((remSleep / remSleepTarget) * remSleepWeight, remSleepWeight)

        // Efficiency score (20 pts max)
        var efficiencyScore: Double
        if timeInBed > 0 {
            let efficiency = min(totalSleep / timeInBed, 1.0)  // Cap at 100%
            efficiencyScore = efficiency * efficiencyWeight
        } else {
            efficiencyScore = 15.0  // Default if no in-bed data
        }

        return durationScore + deepScore + remScore + efficiencyScore
    }

    /// Get breakdown of score components
    static func breakdown(from healthData: [String: String]) -> SleepScoreBreakdown? {
        guard let totalSleep = extractDouble(healthData, key: "Sleep Analysis [Total] (hr)"),
              totalSleep > 0 else {
            return nil
        }

        let deepSleep = extractDouble(healthData, key: "Sleep Analysis [Deep] (hr)") ?? 0
        let remSleep = extractDouble(healthData, key: "Sleep Analysis [REM] (hr)") ?? 0
        let inBed = extractDouble(healthData, key: "Sleep Analysis [In Bed] (hr)") ?? 0

        let durationScore = min((totalSleep / durationTarget) * durationWeight, durationWeight)
        let deepScore = min((deepSleep / deepSleepTarget) * deepSleepWeight, deepSleepWeight)
        let remScore = min((remSleep / remSleepTarget) * remSleepWeight, remSleepWeight)

        var efficiencyScore: Double
        var efficiency: Double?
        if inBed > 0 {
            efficiency = min(totalSleep / inBed, 1.0)
            efficiencyScore = efficiency! * efficiencyWeight
        } else {
            efficiencyScore = 15.0
        }

        return SleepScoreBreakdown(
            totalScore: durationScore + deepScore + remScore + efficiencyScore,
            durationScore: durationScore,
            durationActual: totalSleep,
            durationTarget: durationTarget,
            deepSleepScore: deepScore,
            deepSleepActual: deepSleep,
            deepSleepTarget: deepSleepTarget,
            remSleepScore: remScore,
            remSleepActual: remSleep,
            remSleepTarget: remSleepTarget,
            efficiencyScore: efficiencyScore,
            efficiency: efficiency
        )
    }

    /// Classify score into status
    static func status(for score: Double) -> SleepScoreStatus {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .good
        case 60..<70: return .fair
        default: return .poor
        }
    }

    private static func extractDouble(_ dict: [String: String], key: String) -> Double? {
        guard let value = dict[key], !value.isEmpty else { return nil }
        return Double(value)
    }
}

// MARK: - Data Models

struct SleepScoreBreakdown {
    let totalScore: Double

    let durationScore: Double
    let durationActual: Double
    let durationTarget: Double

    let deepSleepScore: Double
    let deepSleepActual: Double
    let deepSleepTarget: Double

    let remSleepScore: Double
    let remSleepActual: Double
    let remSleepTarget: Double

    let efficiencyScore: Double
    let efficiency: Double?

    var durationPercentage: Double { (durationActual / durationTarget) * 100 }
    var deepSleepPercentage: Double { (deepSleepActual / deepSleepTarget) * 100 }
    var remSleepPercentage: Double { (remSleepActual / remSleepTarget) * 100 }
}

enum SleepScoreStatus: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
}
