extension Dictionary {
    func mapKeys<T>(_ transform: (Key) throws -> T) rethrows -> [T: Value] where T: Hashable {
        var transformed: [T: Value] = [:]
        for (key, value) in self {
            transformed[try transform(key)] = value
        }
        return transformed
    }
    
    func filterValues(_ isIncluded: (Value) throws -> Bool) rethrows -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in self {
            if try isIncluded(value) {
                result[key] = value
            }
        }
        return result
    }
    
    func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> [Key: T] {
        var result: [Key: T] = [:]
        for (key, value) in self {
            if let transformedValue = try transform(value) {
                result[key] = transformedValue
            }
        }
        return result
    }
}
