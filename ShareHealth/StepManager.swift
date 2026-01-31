import Foundation
import HealthKit

class StepManager: ObservableObject {
    let healthStore = HKHealthStore()
    
    func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ [HEALTH] HealthKit not available")
            completion(false)
            return
        }

        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let typesToReadWrite: Set = [stepType]
        
        let status = healthStore.authorizationStatus(for: stepType)
        
        switch status {
        case .sharingAuthorized:
            print("✅ [AUTH] HealthKit already authorized")
            HealthKitManager.shared.setAuthorized(true)
            completion(true)
            
        case .notDetermined:
            print("🔐 [AUTH] Requesting authorization...")
            healthStore.requestAuthorization(toShare: typesToReadWrite, read: typesToReadWrite) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ [AUTH] Authorization granted")
                        HealthKitManager.shared.setAuthorized(true)
                    } else {
                        print("❌ [AUTH] Authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                        HealthKitManager.shared.setAuthorized(false)
                    }
                    completion(success)
                }
            }
            
        case .sharingDenied:
            print("❌ [AUTH] HealthKit access denied")
            HealthKitManager.shared.setAuthorized(false)
            completion(false)
            
        @unknown default:
            print("❌ [AUTH] Unknown authorization status")
            HealthKitManager.shared.setAuthorized(false)
            completion(false)
        }
    }

    func fetchHourlySteps(start: Date, end: Date, completion: @escaping ([String: Int]) -> Void) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        var hourlySteps: [String: Int] = [:]
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: start)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: current)!
        
        print("\n📊 [FETCH] Getting steps for \(formatDebugDate(start))")
        
        let group = DispatchGroup()
        
        // Pre-fill all hours with 0
        for hour in 0...23 {
            hourlySteps["\(hour)"] = 0
        }

        while current < endOfDay {
            group.enter()
            
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: current)!
            let hour = calendar.component(.hour, from: current)
            
            let predicate = HKQuery.predicateForSamples(
                withStart: current,
                end: nextHour,
                options: .strictStartDate
            )
            
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                defer { group.leave() }
                
                if let sum = result?.sumQuantity() {
                    let steps = Int(sum.doubleValue(for: HKUnit.count()))
                    if steps > 0 {
                        print("   Hour \(String(format: "%02d", hour)): \(steps)")
                        hourlySteps["\(hour)"] = steps
                    }
                }
            }
            
            healthStore.execute(query)
            current = nextHour
        }

        group.notify(queue: .main) {
            let total = hourlySteps.values.reduce(0, +)
            print("\n   Total steps: \(total)")
            completion(hourlySteps)
        }
    }

    func modifySteps(for date: Date, steps: [String: Int], completion: @escaping (Bool, String?) -> Void) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        print("\n[MODIFY] Adding steps for \(formatDebugDate(date))")
        
        var samples: [HKQuantitySample] = []
        
        // Create samples for each hour with steps
        for (hourStr, stepCount) in steps where stepCount > 0 {
            guard let hour = Int(hourStr) else { continue }
            
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = 0
            components.second = 0
            
            if let startTime = calendar.date(from: components),
               let endTime = calendar.date(byAdding: .hour, value: 1, to: startTime) {
                
                let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: Double(stepCount))
                let metadata: [String: Any] = [
                    HKMetadataKeyExternalUUID: UUID().uuidString,
                    "Source": "SharedSteps"
                ]
                
                let sample = HKQuantitySample(
                    type: stepType,
                    quantity: quantity,
                    start: startTime,
                    end: endTime,
                    metadata: metadata
                )
                
                samples.append(sample)
                print("   Hour \(String(format: "%02d", hour)): \(stepCount)")
            }
        }
        
        print("\n💾 [MODIFY] Writing \(samples.count) hourly samples...")
        
        healthStore.save(samples) { success, error in
            if success {
                let totalSteps = steps.values.reduce(0, +)
                print("✅ [MODIFY] Successfully wrote step data")
                print("   Total steps: \(totalSteps)")
                
                // Add delay before completion to ensure data is fully available
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    completion(true, "Successfully added \(totalSteps) steps")
                }
            } else {
                print("❌ [MODIFY] Failed to write data: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    completion(false, "Failed to add steps")
                }
            }
        }
    }
    
    private func formatDebugDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
