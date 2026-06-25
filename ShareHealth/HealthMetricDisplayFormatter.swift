import Foundation

enum HealthMetricDisplayFormatter {
    static func formatPrediction(_ value: Double, for targetId: String, displayName: String? = nil) -> String {
        let displayTargetId = HealthMetricTargetAliases.canonicalDisplayTargetId(targetId, displayName: displayName)
        switch displayTargetId {
        case "sleepScore":
            return String(format: "%.0f", clamped(value, lower: 0, upper: 100))
        case "hrv":
            return String(format: "%.0f ms", max(0, value))
        case "restingHR":
            return String(format: "%.0f bpm", max(0, value))
        default:
            return formatCustomPrediction(value, for: displayTargetId)
        }
    }

    static func formatDelta(_ value: Double, for targetId: String, displayName: String? = nil) -> String {
        let unit = unitLabel(for: targetId, displayName: displayName)

        switch unit {
        case "lb", "kg", "hr", "g", "cm", "in", "ft", "yd", "m", "mi", "mi/hr", "fl_oz_us", "L":
            return "\(String(format: "%+.1f", value)) \(unit)"
        case "kcal", "min", "count", "ms", "mg", "mcg", "W":
            return "\(String(format: "%+.0f", value)) \(unit)"
        case "%":
            return String(format: "%+.1f%%", value)
        case "count/min":
            return String(format: "%+.0f /min", value)
        case "":
            return String(format: "%+.1f", value)
        default:
            return "\(String(format: "%+.1f", value)) \(unit)"
        }
    }

    static func unitLabel(for targetId: String, displayName: String? = nil) -> String {
        let displayTargetId = HealthMetricTargetAliases.canonicalDisplayTargetId(targetId, displayName: displayName)
        switch displayTargetId {
        case "sleepScore": return "score"
        case "hrv": return "ms"
        case "restingHR": return "bpm"
        default:
            return parenthesizedSuffix(in: displayTargetId) ?? ""
        }
    }

    private static func formatCustomPrediction(_ value: Double, for targetId: String) -> String {
        let nonNegativeValue = max(0, value)
        guard let unit = parenthesizedSuffix(in: targetId) else {
            return String(format: "%.1f", value)
        }

        switch unit {
        case "lb", "kg":
            return "\(String(format: "%.1f", nonNegativeValue)) \(unit)"
        case "kcal", "min", "count", "ms", "mg", "mcg", "W":
            return "\(String(format: "%.0f", nonNegativeValue)) \(unit)"
        case "%":
            return String(format: "%.1f%%", clamped(value, lower: 0, upper: 100))
        case "count/min":
            return String(format: "%.0f /min", nonNegativeValue)
        case "hr", "g", "cm", "in", "ft", "yd", "m", "mi", "mi/hr", "fl_oz_us", "L":
            return "\(String(format: "%.1f", nonNegativeValue)) \(unit)"
        default:
            return "\(String(format: "%.1f", nonNegativeValue)) \(unit)"
        }
    }

    private static func parenthesizedSuffix(in targetId: String) -> String? {
        guard targetId.hasSuffix(")"),
              let openIndex = targetId.lastIndex(of: "(") else {
            return nil
        }

        let start = targetId.index(after: openIndex)
        let end = targetId.index(before: targetId.endIndex)
        guard start < end else { return nil }
        return String(targetId[start..<end])
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
