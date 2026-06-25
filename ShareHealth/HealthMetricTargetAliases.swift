import Foundation

enum HealthMetricTargetAliases {
    static func lookupKeys(for targetId: String, displayName: String? = nil) -> [String] {
        let canonicalId = canonicalDisplayTargetId(targetId, displayName: displayName)

        if isLeanBodyMass(targetId) || isLeanBodyMass(displayName) || isLeanBodyMass(canonicalId) {
            return unique([
                targetId,
                displayName,
                canonicalId,
                "Lean Body Mass (lb)",
                "Lean Body Mass (count)",
                "Lean Body Mass"
            ].compactMap { $0 })
        }

        if isWeight(targetId) || isWeight(displayName) || isWeight(canonicalId) {
            return unique([
                targetId,
                displayName,
                canonicalId,
                "Weight (lb)",
                "Weight (count)"
            ].compactMap { $0 })
        }

        return [targetId]
    }

    static func canonicalDisplayTargetId(_ targetId: String, displayName: String? = nil) -> String {
        if isLeanBodyMass(targetId) || isLeanBodyMass(displayName) {
            return "Lean Body Mass (lb)"
        }

        if isWeight(targetId) || isWeight(displayName) {
            return "Weight (lb)"
        }

        return targetId
    }

    static func isLeanBodyMass(_ value: String?) -> Bool {
        guard let value = value else { return false }
        let normalized = value.lowercased()
        let compact = normalized.filter { $0.isLetter || $0.isNumber }
        return normalized.contains("lean body")
            || normalized.contains("lean mass")
            || compact.contains("leanbodymass")
            || compact.contains("leanmass")
            || compact.contains("hkquantitytypeidentifierleanbodymass")
    }

    private static func isWeight(_ value: String?) -> Bool {
        guard let value = value else { return false }
        let normalized = value.lowercased()
        let compact = normalized.filter { $0.isLetter || $0.isNumber }
        return normalized == "bodymass"
            || normalized.contains("weight")
            || compact == "bodymass"
            || compact.contains("bodyweight")
            || compact.contains("hkquantitytypeidentifierbodymass")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
