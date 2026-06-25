import Foundation

enum HealthMetricDiagnostics {
    private static var stamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return "ShareHealthMetricDebug \(formatter.string(from: Date()))"
    }

    static func logModelDetailInput(targetId: String, targetName: String, captures: [StoredFaceCapture]) {
        let effectiveTargetId = HealthMetricTargetAliases.canonicalDisplayTargetId(targetId, displayName: targetName)
        let lookupKeys = HealthMetricTargetAliases.lookupKeys(for: targetId, displayName: targetName)

        print("\(stamp) ModelCVDetail input targetId='\(targetId)' targetName='\(targetName)' effectiveTargetId='\(effectiveTargetId)' lookupKeys=\(lookupKeys) captures=\(captures.count)")

        let relatedKeys = relatedHealthKeys(in: captures)
        if relatedKeys.isEmpty {
            print("\(stamp) Related health keys: none found")
        } else {
            print("\(stamp) Related health keys (\(relatedKeys.count)): \(relatedKeys.prefix(30).joined(separator: " | "))")
        }

        logHealthKeyStats(title: "Lookup key stats", keys: lookupKeys, captures: captures)

        let leanKeys = relatedKeys.filter { HealthMetricTargetAliases.isLeanBodyMass($0) }
        if !leanKeys.isEmpty {
            logHealthKeyStats(title: "Lean-body related key stats", keys: leanKeys, captures: captures)
        }
    }

    static func logCVSeries(context: String, targetId: String, targetName: String? = nil, actuals: [Double], predictions: [Double]) {
        let effectiveTargetId = HealthMetricTargetAliases.canonicalDisplayTargetId(targetId, displayName: targetName)
        print("\(stamp) \(context) targetId='\(targetId)' targetName='\(targetName ?? "")' effectiveTargetId='\(effectiveTargetId)' actuals=\(describe(actuals)) predictions=\(describe(predictions))")
    }

    private static func logHealthKeyStats(title: String, keys: [String], captures: [StoredFaceCapture]) {
        guard !keys.isEmpty else { return }

        for key in keys {
            let values = captures.compactMap { capture -> Double? in
                guard let stringValue = capture.healthData?[key] else { return nil }
                return Double(stringValue)
            }

            if values.isEmpty {
                print("\(stamp) \(title): '\(key)' no numeric values")
            } else {
                print("\(stamp) \(title): '\(key)' \(describe(values))")
            }
        }
    }

    private static func relatedHealthKeys(in captures: [StoredFaceCapture]) -> [String] {
        var keys = Set<String>()

        for capture in captures {
            guard let healthData = capture.healthData else { continue }
            for key in healthData.keys {
                let lowercasedKey = key.lowercased()
                if lowercasedKey.contains("lean")
                    || lowercasedKey.contains("mass")
                    || lowercasedKey.contains("weight")
                    || lowercasedKey.contains("body")
                    || lowercasedKey.contains("energy") {
                    keys.insert(key)
                }
            }
        }

        return keys.sorted()
    }

    private static func describe(_ values: [Double]) -> String {
        let finiteValues = values.filter { $0.isFinite }.sorted()
        guard let min = finiteValues.first, let max = finiteValues.last else {
            return "count=0"
        }

        let median = median(ofSortedValues: finiteValues)
        let samples = finiteValues.prefix(5).map { String(format: "%.3f", $0) }.joined(separator: ", ")
        return "count=\(finiteValues.count) min=\(String(format: "%.3f", min)) median=\(String(format: "%.3f", median)) max=\(String(format: "%.3f", max)) samples=[\(samples)]"
    }

    private static func median(ofSortedValues values: [Double]) -> Double {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}
