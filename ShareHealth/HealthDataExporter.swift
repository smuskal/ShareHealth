import Foundation
import HealthKit

/// Represents a single health metric configuration
struct HealthMetric {
    let identifier: HKQuantityTypeIdentifier
    let csvHeader: String
    let unit: HKUnit
    let aggregation: AggregationType

    enum AggregationType {
        case sum
        case average
        case min
        case max
        case mostRecent
    }
}

class HealthDataExporter: ObservableObject {
    let healthStore = HKHealthStore()

    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var currentMetric: String = ""
    @Published var exportedFilePath: URL?
    @Published var errorMessage: String?

    // All quantity metrics matching the CSV format - only using valid identifiers
    private let quantityMetrics: [HealthMetric] = [
        // Energy
        HealthMetric(identifier: .activeEnergyBurned, csvHeader: "Active Energy (kcal)", unit: .kilocalorie(), aggregation: .sum),
        HealthMetric(identifier: .basalEnergyBurned, csvHeader: "Resting Energy (kcal)", unit: .kilocalorie(), aggregation: .sum),
        HealthMetric(identifier: .dietaryEnergyConsumed, csvHeader: "Dietary Energy (kcal)", unit: .kilocalorie(), aggregation: .sum),

        // Activity
        HealthMetric(identifier: .appleExerciseTime, csvHeader: "Apple Exercise Time (min)", unit: .minute(), aggregation: .sum),
        HealthMetric(identifier: .appleMoveTime, csvHeader: "Apple Move Time (min)", unit: .minute(), aggregation: .sum),
        HealthMetric(identifier: .appleStandTime, csvHeader: "Apple Stand Time (min)", unit: .minute(), aggregation: .sum),
        HealthMetric(identifier: .stepCount, csvHeader: "Step Count (count)", unit: .count(), aggregation: .sum),
        HealthMetric(identifier: .flightsClimbed, csvHeader: "Flights Climbed (count)", unit: .count(), aggregation: .sum),
        HealthMetric(identifier: .distanceWalkingRunning, csvHeader: "Walking + Running Distance (mi)", unit: .mile(), aggregation: .sum),
        HealthMetric(identifier: .distanceCycling, csvHeader: "Cycling Distance (mi)", unit: .mile(), aggregation: .sum),
        HealthMetric(identifier: .distanceSwimming, csvHeader: "Swimming Distance (yd)", unit: .yard(), aggregation: .sum),
        HealthMetric(identifier: .distanceDownhillSnowSports, csvHeader: "Distance Downhill Snow Sports (mi)", unit: .mile(), aggregation: .sum),
        HealthMetric(identifier: .distanceWheelchair, csvHeader: "Wheelchair Distance (mi)", unit: .mile(), aggregation: .sum),
        HealthMetric(identifier: .pushCount, csvHeader: "Push Count (count)", unit: .count(), aggregation: .sum),
        HealthMetric(identifier: .swimmingStrokeCount, csvHeader: "Swimming Stroke Count (count)", unit: .count(), aggregation: .sum),

        // Heart
        HealthMetric(identifier: .heartRate, csvHeader: "Heart Rate [Avg] (count/min)", unit: HKUnit.count().unitDivided(by: .minute()), aggregation: .average),
        HealthMetric(identifier: .restingHeartRate, csvHeader: "Resting Heart Rate (count/min)", unit: HKUnit.count().unitDivided(by: .minute()), aggregation: .average),
        HealthMetric(identifier: .walkingHeartRateAverage, csvHeader: "Walking Heart Rate Average (count/min)", unit: HKUnit.count().unitDivided(by: .minute()), aggregation: .average),
        HealthMetric(identifier: .heartRateVariabilitySDNN, csvHeader: "Heart Rate Variability (ms)", unit: .secondUnit(with: .milli), aggregation: .average),

        // Respiratory
        HealthMetric(identifier: .respiratoryRate, csvHeader: "Respiratory Rate (count/min)", unit: HKUnit.count().unitDivided(by: .minute()), aggregation: .average),
        HealthMetric(identifier: .oxygenSaturation, csvHeader: "Blood Oxygen Saturation (%)", unit: .percent(), aggregation: .average),
        HealthMetric(identifier: .vo2Max, csvHeader: "VO2 Max (ml/(kg·min))", unit: HKUnit(from: "ml/kg*min"), aggregation: .average),
        HealthMetric(identifier: .peakExpiratoryFlowRate, csvHeader: "Peak Expiratory Flow Rate (L/min)", unit: HKUnit.liter().unitDivided(by: .minute()), aggregation: .average),
        HealthMetric(identifier: .forcedExpiratoryVolume1, csvHeader: "Forced Expiratory Volume 1 (L)", unit: .liter(), aggregation: .average),
        HealthMetric(identifier: .forcedVitalCapacity, csvHeader: "Forced Vital Capacity (L)", unit: .liter(), aggregation: .average),

        // Body Measurements
        HealthMetric(identifier: .height, csvHeader: "Height (cm)", unit: .meterUnit(with: .centi), aggregation: .average),
        HealthMetric(identifier: .bodyMass, csvHeader: "Weight (lb)", unit: .pound(), aggregation: .average),
        HealthMetric(identifier: .bodyMassIndex, csvHeader: "Body Mass Index (count)", unit: .count(), aggregation: .average),
        HealthMetric(identifier: .bodyFatPercentage, csvHeader: "Body Fat Percentage (%)", unit: .percent(), aggregation: .average),
        HealthMetric(identifier: .leanBodyMass, csvHeader: "Lean Body Mass (lb)", unit: .pound(), aggregation: .average),
        HealthMetric(identifier: .waistCircumference, csvHeader: "Waist Circumference (in)", unit: .inch(), aggregation: .average),

        // Vitals
        HealthMetric(identifier: .bodyTemperature, csvHeader: "Body Temperature (degF)", unit: .degreeFahrenheit(), aggregation: .average),
        HealthMetric(identifier: .basalBodyTemperature, csvHeader: "Basal Body Temperature (degF)", unit: .degreeFahrenheit(), aggregation: .average),
        HealthMetric(identifier: .bloodGlucose, csvHeader: "Blood Glucose (mg/dL)", unit: HKUnit(from: "mg/dL"), aggregation: .average),
        HealthMetric(identifier: .electrodermalActivity, csvHeader: "Electrodermal Activity (mcS)", unit: .siemen(), aggregation: .average),
        HealthMetric(identifier: .bloodAlcoholContent, csvHeader: "Blood Alcohol Content (%)", unit: .percent(), aggregation: .average),
        HealthMetric(identifier: .peripheralPerfusionIndex, csvHeader: "Peripheral Perfusion Index (%)", unit: .percent(), aggregation: .average),

        // Blood Pressure
        HealthMetric(identifier: .bloodPressureSystolic, csvHeader: "Blood Pressure [Systolic] (mmHg)", unit: .millimeterOfMercury(), aggregation: .average),
        HealthMetric(identifier: .bloodPressureDiastolic, csvHeader: "Blood Pressure [Diastolic] (mmHg)", unit: .millimeterOfMercury(), aggregation: .average),

        // Nutrition
        HealthMetric(identifier: .dietaryProtein, csvHeader: "Protein (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryCarbohydrates, csvHeader: "Carbohydrates (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryFatTotal, csvHeader: "Total Fat (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryFatSaturated, csvHeader: "Saturated Fat (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryFatMonounsaturated, csvHeader: "Monounsaturated Fat (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryFatPolyunsaturated, csvHeader: "Polyunsaturated Fat (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryCholesterol, csvHeader: "Cholesterol (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietarySugar, csvHeader: "Sugar (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietaryFiber, csvHeader: "Fiber (g)", unit: .gram(), aggregation: .sum),
        HealthMetric(identifier: .dietarySodium, csvHeader: "Sodium (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryPotassium, csvHeader: "Potassium (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryCalcium, csvHeader: "Calcium (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryIron, csvHeader: "Iron (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryMagnesium, csvHeader: "Magnesium (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryPhosphorus, csvHeader: "Phosphorus (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryZinc, csvHeader: "Zinc (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryCopper, csvHeader: "Copper (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryManganese, csvHeader: "Manganese (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietarySelenium, csvHeader: "Selenium (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryChromium, csvHeader: "Chromium (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryMolybdenum, csvHeader: "Molybdenum (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryChloride, csvHeader: "Chloride (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryIodine, csvHeader: "Iodine (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminA, csvHeader: "Vitamin A (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminB6, csvHeader: "Vitamin B6 (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminB12, csvHeader: "Vitamin B12 (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminC, csvHeader: "Vitamin C (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminD, csvHeader: "Vitamin D (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminE, csvHeader: "Vitamin E (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryVitaminK, csvHeader: "Vitamin K (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryThiamin, csvHeader: "Thiamin (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryRiboflavin, csvHeader: "Riboflavin (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryNiacin, csvHeader: "Niacin (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryFolate, csvHeader: "Folate (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryBiotin, csvHeader: "Biotin (mcg)", unit: HKUnit.gramUnit(with: .micro), aggregation: .sum),
        HealthMetric(identifier: .dietaryPantothenicAcid, csvHeader: "Pantothenic Acid (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryCaffeine, csvHeader: "Caffeine (mg)", unit: HKUnit.gramUnit(with: .milli), aggregation: .sum),
        HealthMetric(identifier: .dietaryWater, csvHeader: "Water (fl_oz_us)", unit: .fluidOunceUS(), aggregation: .sum),

        // Alcohol
        HealthMetric(identifier: .numberOfAlcoholicBeverages, csvHeader: "Alcohol Consumption (count)", unit: .count(), aggregation: .sum),

        // Mobility
        HealthMetric(identifier: .walkingSpeed, csvHeader: "Walking Speed (mi/hr)", unit: HKUnit.mile().unitDivided(by: .hour()), aggregation: .average),
        HealthMetric(identifier: .walkingStepLength, csvHeader: "Walking Step Length (in)", unit: .inch(), aggregation: .average),
        HealthMetric(identifier: .walkingAsymmetryPercentage, csvHeader: "Walking Asymmetry Percentage (%)", unit: .percent(), aggregation: .average),
        HealthMetric(identifier: .walkingDoubleSupportPercentage, csvHeader: "Walking Double Support Percentage (%)", unit: .percent(), aggregation: .average),
        HealthMetric(identifier: .stairAscentSpeed, csvHeader: "Stair Speed: Up (ft/s)", unit: HKUnit.foot().unitDivided(by: .second()), aggregation: .average),
        HealthMetric(identifier: .stairDescentSpeed, csvHeader: "Stair Speed: Down (ft/s)", unit: HKUnit.foot().unitDivided(by: .second()), aggregation: .average),
        HealthMetric(identifier: .sixMinuteWalkTestDistance, csvHeader: "Six-Minute Walking Test Distance (m)", unit: .meter(), aggregation: .average),

        // Audio Exposure
        HealthMetric(identifier: .environmentalAudioExposure, csvHeader: "Environmental Audio Exposure (dBASPL)", unit: .decibelAWeightedSoundPressureLevel(), aggregation: .average),
        HealthMetric(identifier: .headphoneAudioExposure, csvHeader: "Headphone Audio Exposure (dBASPL)", unit: .decibelAWeightedSoundPressureLevel(), aggregation: .average),

        // Other
        HealthMetric(identifier: .numberOfTimesFallen, csvHeader: "Number of Times Fallen (count)", unit: .count(), aggregation: .sum),
        HealthMetric(identifier: .inhalerUsage, csvHeader: "Inhaler Usage (count)", unit: .count(), aggregation: .sum),
        HealthMetric(identifier: .insulinDelivery, csvHeader: "Insulin Delivery (IU)", unit: .internationalUnit(), aggregation: .sum),
        HealthMetric(identifier: .uvExposure, csvHeader: "UV Exposure (count)", unit: .count(), aggregation: .average),

        // Running Metrics
        HealthMetric(identifier: .runningGroundContactTime, csvHeader: "Running Ground Contact Time (ms)", unit: .secondUnit(with: .milli), aggregation: .average),
        HealthMetric(identifier: .runningPower, csvHeader: "Running Power (W)", unit: .watt(), aggregation: .average),
        HealthMetric(identifier: .runningSpeed, csvHeader: "Running Speed (mi/hr)", unit: HKUnit.mile().unitDivided(by: .hour()), aggregation: .average),
        HealthMetric(identifier: .runningStrideLength, csvHeader: "Running Stride Length (m)", unit: .meter(), aggregation: .average),
        HealthMetric(identifier: .runningVerticalOscillation, csvHeader: "Running Vertical Oscillation (cm)", unit: .meterUnit(with: .centi), aggregation: .average),

        // Cycling Metrics
        HealthMetric(identifier: .cyclingCadence, csvHeader: "Cycling Cadence (count/min)", unit: HKUnit.count().unitDivided(by: .minute()), aggregation: .average),
        HealthMetric(identifier: .cyclingFunctionalThresholdPower, csvHeader: "Cycling Functional Threshold Power (W)", unit: .watt(), aggregation: .average),
        HealthMetric(identifier: .cyclingPower, csvHeader: "Cycling Power (W)", unit: .watt(), aggregation: .average),
        HealthMetric(identifier: .cyclingSpeed, csvHeader: "Cycling Speed (mi/hr)", unit: HKUnit.mile().unitDivided(by: .hour()), aggregation: .average),

        // Temperature
        HealthMetric(identifier: .appleSleepingWristTemperature, csvHeader: "Apple Sleeping Wrist Temperature (degF)", unit: .degreeFahrenheit(), aggregation: .average),
        HealthMetric(identifier: .waterTemperature, csvHeader: "Underwater Temperature (degF)", unit: .degreeFahrenheit(), aggregation: .average),

        // Cardio/Respiratory
        HealthMetric(identifier: .atrialFibrillationBurden, csvHeader: "Atrial Fibrillation Burden (%)", unit: .percent(), aggregation: .average),

        // Physical Activity
        HealthMetric(identifier: .physicalEffort, csvHeader: "Physical Effort (kcal/hr·kg)", unit: HKUnit.kilocalorie().unitDivided(by: .hour()).unitDivided(by: HKUnit.gramUnit(with: .kilo)), aggregation: .average),
        HealthMetric(identifier: .timeInDaylight, csvHeader: "Time in Daylight (min)", unit: .minute(), aggregation: .sum),

        // Underwater
        HealthMetric(identifier: .underwaterDepth, csvHeader: "Underwater Depth (ft)", unit: .foot(), aggregation: .average),
    ]

    // CSV column order matching the example file
    private let csvColumnOrder: [String] = [
        "Date/Time",
        "Active Energy (kcal)",
        "Alcohol Consumption (count)",
        "Apple Exercise Time (min)",
        "Apple Move Time (min)",
        "Apple Sleeping Wrist Temperature (degF)",
        "Apple Stand Hour (count)",
        "Apple Stand Time (min)",
        "Atrial Fibrillation Burden (%)",
        "Basal Body Temperature (degF)",
        "Biotin (mcg)",
        "Blood Alcohol Content (%)",
        "Blood Glucose (mg/dL)",
        "Blood Oxygen Saturation (%)",
        "Blood Pressure [Systolic] (mmHg)",
        "Blood Pressure [Diastolic] (mmHg)",
        "Body Fat Percentage (%)",
        "Body Mass Index (count)",
        "Body Temperature (degF)",
        "Breathing Disturbances (count)",
        "Caffeine (mg)",
        "Calcium (mg)",
        "Carbohydrates (g)",
        "Cardio Recovery (count/min)",
        "Chloride (mg)",
        "Cholesterol (mg)",
        "Chromium (mcg)",
        "Copper (mg)",
        "Cycling Cadence (count/min)",
        "Cycling Distance (mi)",
        "Cycling Functional Threshold Power (W)",
        "Cycling Power (W)",
        "Cycling Speed (mi/hr)",
        "Dietary Energy (kcal)",
        "Distance Downhill Snow Sports (mi)",
        "Electrodermal Activity (mcS)",
        "Environmental Audio Exposure (dBASPL)",
        "Fiber (g)",
        "Flights Climbed (count)",
        "Folate (mcg)",
        "Forced Expiratory Volume 1 (L)",
        "Forced Vital Capacity (L)",
        "Handwashing (s)",
        "Headphone Audio Exposure (dBASPL)",
        "Heart Rate [Min] (count/min)",
        "Heart Rate [Max] (count/min)",
        "Heart Rate [Avg] (count/min)",
        "Heart Rate Variability (ms)",
        "Height (cm)",
        "Inhaler Usage (count)",
        "Insulin Delivery (IU)",
        "Iodine (mcg)",
        "Iron (mg)",
        "Lean Body Mass (lb)",
        "Magnesium (mg)",
        "Manganese (mg)",
        "Mindful Minutes (min)",
        "Molybdenum (mcg)",
        "Monounsaturated Fat (g)",
        "Niacin (mg)",
        "Number of Times Fallen (count)",
        "Pantothenic Acid (mg)",
        "Peak Expiratory Flow Rate (L/min)",
        "Peripheral Perfusion Index (%)",
        "Phosphorus (mg)",
        "Physical Effort (kcal/hr·kg)",
        "Polyunsaturated Fat (g)",
        "Potassium (mg)",
        "Protein (g)",
        "Push Count (count)",
        "Respiratory Rate (count/min)",
        "Resting Energy (kcal)",
        "Resting Heart Rate (count/min)",
        "Riboflavin (mg)",
        "Running Ground Contact Time (ms)",
        "Running Power (W)",
        "Running Speed (mi/hr)",
        "Running Stride Length (m)",
        "Running Vertical Oscillation (cm)",
        "Saturated Fat (g)",
        "Selenium (mcg)",
        "Sexual Activity [Unspecified] (count)",
        "Sexual Activity [Protection Used] (count)",
        "Sexual Activity [Protection Not Used] (count)",
        "Six-Minute Walking Test Distance (m)",
        "Sleep Analysis [Total] (hr)",
        "Sleep Analysis [Asleep] (hr)",
        "Sleep Analysis [In Bed] (hr)",
        "Sleep Analysis [Core] (hr)",
        "Sleep Analysis [Deep] (hr)",
        "Sleep Analysis [REM] (hr)",
        "Sleep Analysis [Awake] (hr)",
        "Sodium (mg)",
        "Stair Speed: Down (ft/s)",
        "Stair Speed: Up (ft/s)",
        "Step Count (count)",
        "Sugar (g)",
        "Swimming Distance (yd)",
        "Swimming Stroke Count (count)",
        "Thiamin (mg)",
        "Time in Daylight (min)",
        "Toothbrushing (s)",
        "Total Fat (g)",
        "UV Exposure (count)",
        "Underwater Depth (ft)",
        "Underwater Temperature (degF)",
        "VO2 Max (ml/(kg·min))",
        "Vitamin A (mcg)",
        "Vitamin B12 (mcg)",
        "Vitamin B6 (mg)",
        "Vitamin C (mg)",
        "Vitamin D (mcg)",
        "Vitamin E (mg)",
        "Vitamin K (mcg)",
        "Waist Circumference (in)",
        "Walking + Running Distance (mi)",
        "Walking Asymmetry Percentage (%)",
        "Walking Double Support Percentage (%)",
        "Walking Heart Rate Average (count/min)",
        "Walking Speed (mi/hr)",
        "Walking Step Length (in)",
        "Water (fl_oz_us)",
        "Weight (lb)",
        "Wheelchair Distance (mi)",
        "Zinc (mg)"
    ]

    /// Request authorization for all health data types
    func requestFullAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            completion(false)
            return
        }

        var typesToRead: Set<HKObjectType> = []

        // Add all quantity types
        for metric in quantityMetrics {
            if let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) {
                typesToRead.insert(type)
            }
        }

        // Add category types
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            typesToRead.insert(sleepType)
        }
        if let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            typesToRead.insert(mindfulType)
        }
        if let handwashingType = HKCategoryType.categoryType(forIdentifier: .handwashingEvent) {
            typesToRead.insert(handwashingType)
        }
        if let toothbrushingType = HKCategoryType.categoryType(forIdentifier: .toothbrushingEvent) {
            typesToRead.insert(toothbrushingType)
        }
        if let sexualActivityType = HKCategoryType.categoryType(forIdentifier: .sexualActivity) {
            typesToRead.insert(sexualActivityType)
        }
        if let standHourType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            typesToRead.insert(standHourType)
        }

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Authorization error: \(error.localizedDescription)")
                }
                completion(success)
            }
        }
    }

    /// Export health data for the specified date to CSV
    func exportHealthData(for date: Date, completion: @escaping (URL?, String?) -> Void) {
        DispatchQueue.main.async {
            self.isExporting = true
            self.exportProgress = 0.0
            self.errorMessage = nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion(nil, "Failed to calculate date range")
            return
        }

        var healthData: [String: String] = [:]
        let group = DispatchGroup()
        let totalMetrics = quantityMetrics.count + 6 // +6 for category types
        var completedMetrics = 0

        // Fetch all quantity metrics
        for metric in quantityMetrics {
            group.enter()

            DispatchQueue.main.async {
                self.currentMetric = metric.csvHeader
            }

            fetchQuantityMetric(metric, startDate: startOfDay, endDate: endOfDay) { value in
                if let value = value {
                    healthData[metric.csvHeader] = value
                }

                completedMetrics += 1
                DispatchQueue.main.async {
                    self.exportProgress = Double(completedMetrics) / Double(totalMetrics)
                }

                group.leave()
            }
        }

        // Fetch heart rate min/max separately
        group.enter()
        fetchHeartRateMinMax(startDate: startOfDay, endDate: endOfDay) { minHR, maxHR in
            if let minHR = minHR {
                healthData["Heart Rate [Min] (count/min)"] = minHR
            }
            if let maxHR = maxHR {
                healthData["Heart Rate [Max] (count/min)"] = maxHR
            }
            group.leave()
        }

        // Fetch sleep analysis
        group.enter()
        fetchSleepAnalysis(startDate: startOfDay, endDate: endOfDay) { sleepData in
            for (key, value) in sleepData {
                healthData[key] = value
            }
            completedMetrics += 1
            DispatchQueue.main.async {
                self.exportProgress = Double(completedMetrics) / Double(totalMetrics)
            }
            group.leave()
        }

        // Fetch mindful minutes
        group.enter()
        fetchMindfulMinutes(startDate: startOfDay, endDate: endOfDay) { value in
            if let value = value {
                healthData["Mindful Minutes (min)"] = value
            }
            completedMetrics += 1
            group.leave()
        }

        // Fetch handwashing
        group.enter()
        fetchHandwashing(startDate: startOfDay, endDate: endOfDay) { value in
            if let value = value {
                healthData["Handwashing (s)"] = value
            }
            completedMetrics += 1
            group.leave()
        }

        // Fetch toothbrushing
        group.enter()
        fetchToothbrushing(startDate: startOfDay, endDate: endOfDay) { value in
            if let value = value {
                healthData["Toothbrushing (s)"] = value
            }
            completedMetrics += 1
            group.leave()
        }

        // Fetch stand hours
        group.enter()
        fetchStandHours(startDate: startOfDay, endDate: endOfDay) { value in
            if let value = value {
                healthData["Apple Stand Hour (count)"] = value
            }
            completedMetrics += 1
            group.leave()
        }

        // Fetch sexual activity
        group.enter()
        fetchSexualActivity(startDate: startOfDay, endDate: endOfDay) { unspecified, protectionUsed, protectionNotUsed in
            if let val = unspecified {
                healthData["Sexual Activity [Unspecified] (count)"] = val
            }
            if let val = protectionUsed {
                healthData["Sexual Activity [Protection Used] (count)"] = val
            }
            if let val = protectionNotUsed {
                healthData["Sexual Activity [Protection Not Used] (count)"] = val
            }
            completedMetrics += 1
            group.leave()
        }

        group.notify(queue: .main) {
            // Generate CSV
            let csvURL = self.generateCSV(date: date, data: healthData)

            self.isExporting = false
            self.exportProgress = 1.0
            self.exportedFilePath = csvURL

            completion(csvURL, csvURL == nil ? "Failed to generate CSV" : nil)
        }
    }

    private func fetchQuantityMetric(_ metric: HealthMetric, startDate: Date, endDate: Date, completion: @escaping (String?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: metric.identifier) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        var options: HKStatisticsOptions
        switch metric.aggregation {
        case .sum:
            options = .cumulativeSum
        case .average, .mostRecent:
            options = .discreteAverage
        case .min:
            options = .discreteMin
        case .max:
            options = .discreteMax
        }

        let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, result, _ in
            guard let result = result else {
                completion(nil)
                return
            }

            var value: Double?
            switch metric.aggregation {
            case .sum:
                value = result.sumQuantity()?.doubleValue(for: metric.unit)
            case .average, .mostRecent:
                value = result.averageQuantity()?.doubleValue(for: metric.unit)
            case .min:
                value = result.minimumQuantity()?.doubleValue(for: metric.unit)
            case .max:
                value = result.maximumQuantity()?.doubleValue(for: metric.unit)
            }

            if var value = value {
                // Convert percentage values from decimal (0-1) to percentage (0-100)
                if metric.unit == .percent() {
                    value = value * 100
                }
                completion(self.formatValue(value))
            } else {
                completion(nil)
            }
        }

        healthStore.execute(query)
    }

    private func fetchHeartRateMinMax(startDate: Date, endDate: Date, completion: @escaping (String?, String?) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(nil, nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: [.discreteMin, .discreteMax]) { _, result, _ in
            let minHR = result?.minimumQuantity()?.doubleValue(for: unit)
            let maxHR = result?.maximumQuantity()?.doubleValue(for: unit)

            completion(
                minHR != nil ? self.formatValue(minHR!) : nil,
                maxHR != nil ? self.formatValue(maxHR!) : nil
            )
        }

        healthStore.execute(query)
    }

    private func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([String: String]) -> Void) {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([:])
            return
        }

        // Sleep sessions often start the evening before (e.g., 11 PM) and end in the morning.
        // Query from 6 PM the previous day to capture overnight sleep that ends on the target day.
        let calendar = Calendar.current
        let sleepQueryStart = calendar.date(byAdding: .hour, value: -6, to: startDate) ?? startDate

        // Use no strict options to get any samples that overlap with our range
        let predicate = HKQuery.predicateForSamples(withStart: sleepQueryStart, end: endDate, options: [])

        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var sleepData: [String: String] = [:]

            guard let categorySamples = samples as? [HKCategorySample] else {
                completion([:])
                return
            }

            // Group samples by source to match Apple Health's behavior
            // Apple Health uses a single preferred source for sleep data
            var samplesBySource: [String: [HKCategorySample]] = [:]
            for sample in categorySamples {
                let sourceId = sample.sourceRevision.source.bundleIdentifier
                samplesBySource[sourceId, default: []].append(sample)
            }

            // Score each source - prefer dedicated sleep trackers like Eight Sleep
            func scoreSource(bundleId: String, samples: [HKCategorySample]) -> Int {
                let lowerBundleId = bundleId.lowercased()
                var score = 0

                // Prefer Eight Sleep (highest priority per user settings)
                if lowerBundleId.contains("eightsleep") || lowerBundleId.contains("8sleep") {
                    score += 100000
                }
                // Then Oura/Aura
                else if lowerBundleId.contains("oura") || lowerBundleId.contains("aura") {
                    score += 50000
                }
                // Apple Health sources are lower priority
                else if lowerBundleId.hasPrefix("com.apple.") {
                    score += 1000
                }

                // Also prefer sources with detailed sleep stages
                var hasCore = false, hasDeep = false, hasREM = false
                for sample in samples {
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue: hasCore = true
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: hasDeep = true
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: hasREM = true
                    default: break
                    }
                }
                if hasCore { score += 100 }
                if hasDeep { score += 100 }
                if hasREM { score += 100 }
                score += samples.count

                return score
            }

            // Select the source with highest priority (Eight Sleep > Oura > Apple)
            let selectedSource = samplesBySource.max { scoreSource(bundleId: $0.key, samples: $0.value) < scoreSource(bundleId: $1.key, samples: $1.value) }?.key ?? ""
            let selectedSamples = samplesBySource[selectedSource] ?? []

            // Debug: print which source was selected
            print("🛏️ [SLEEP] Selected source: \(selectedSource) with \(selectedSamples.count) samples")

            // Priority order for resolving overlaps within the same source
            let priorityOrder: [Int: Int] = [
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue: 6,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue: 5,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue: 4,
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: 3,
                HKCategoryValueSleepAnalysis.awake.rawValue: 2,
                HKCategoryValueSleepAnalysis.inBed.rawValue: 1
            ]

            // Create tagged intervals with category
            // For sleep, we include the full session that ENDS on the target day
            // (e.g., sleep from 11 PM previous day to 7 AM target day all counts for target day)
            var taggedIntervals: [(start: Date, end: Date, category: Int)] = []
            for sample in selectedSamples {
                // Include samples that end within the target day (midnight to midnight)
                // This captures "last night's sleep" fully
                if sample.endDate > startDate && sample.endDate <= endDate {
                    taggedIntervals.append((start: sample.startDate, end: sample.endDate, category: sample.value))
                }
            }

            // Sort by start time, then by priority (higher priority first for same start)
            taggedIntervals.sort { a, b in
                if a.start != b.start {
                    return a.start < b.start
                }
                return (priorityOrder[a.category] ?? 0) > (priorityOrder[b.category] ?? 0)
            }

            // Build timeline: for each moment in time, track which category applies
            // Use a sweep line algorithm to handle overlaps
            var events: [(time: Date, isStart: Bool, category: Int, id: Int)] = []
            for (idx, interval) in taggedIntervals.enumerated() {
                events.append((time: interval.start, isStart: true, category: interval.category, id: idx))
                events.append((time: interval.end, isStart: false, category: interval.category, id: idx))
            }

            // Sort events by time, with end events before start events at same time
            events.sort { a, b in
                if a.time != b.time {
                    return a.time < b.time
                }
                // End events before start events
                if a.isStart != b.isStart {
                    return !a.isStart
                }
                return false
            }

            // Sweep through events tracking active intervals
            var activeIntervals: Set<Int> = []
            var categoryDurations: [Int: TimeInterval] = [:]
            var lastTime: Date? = nil

            for event in events {
                if let last = lastTime, !activeIntervals.isEmpty {
                    // Find highest priority active category
                    var highestPriority = 0
                    var bestCategory = -1
                    for id in activeIntervals {
                        let cat = taggedIntervals[id].category
                        let priority = priorityOrder[cat] ?? 0
                        if priority > highestPriority {
                            highestPriority = priority
                            bestCategory = cat
                        }
                    }

                    if bestCategory >= 0 {
                        let duration = event.time.timeIntervalSince(last)
                        categoryDurations[bestCategory, default: 0] += duration
                    }
                }

                if event.isStart {
                    activeIntervals.insert(event.id)
                } else {
                    activeIntervals.remove(event.id)
                }

                lastTime = event.time
            }

            // Extract durations by category
            let inBedTime = categoryDurations[HKCategoryValueSleepAnalysis.inBed.rawValue] ?? 0
            let coreTime = categoryDurations[HKCategoryValueSleepAnalysis.asleepCore.rawValue] ?? 0
            let deepTime = categoryDurations[HKCategoryValueSleepAnalysis.asleepDeep.rawValue] ?? 0
            let remTime = categoryDurations[HKCategoryValueSleepAnalysis.asleepREM.rawValue] ?? 0
            let awakeTime = categoryDurations[HKCategoryValueSleepAnalysis.awake.rawValue] ?? 0
            let unspecifiedTime = categoryDurations[HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue] ?? 0

            let asleepTime = coreTime + deepTime + remTime + unspecifiedTime
            let totalSleep = asleepTime + inBedTime

            if totalSleep > 0 { sleepData["Sleep Analysis [Total] (hr)"] = self.formatValue(totalSleep / 3600.0) }
            if asleepTime > 0 { sleepData["Sleep Analysis [Asleep] (hr)"] = self.formatValue(asleepTime / 3600.0) }
            if inBedTime > 0 { sleepData["Sleep Analysis [In Bed] (hr)"] = self.formatValue(inBedTime / 3600.0) }
            if coreTime > 0 { sleepData["Sleep Analysis [Core] (hr)"] = self.formatValue(coreTime / 3600.0) }
            if deepTime > 0 { sleepData["Sleep Analysis [Deep] (hr)"] = self.formatValue(deepTime / 3600.0) }
            if remTime > 0 { sleepData["Sleep Analysis [REM] (hr)"] = self.formatValue(remTime / 3600.0) }
            if awakeTime > 0 { sleepData["Sleep Analysis [Awake] (hr)"] = self.formatValue(awakeTime / 3600.0) }

            completion(sleepData)
        }

        healthStore.execute(query)
    }

    private func fetchMindfulMinutes(startDate: Date, endDate: Date, completion: @escaping (String?) -> Void) {
        guard let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let categorySamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }

            var totalMinutes: TimeInterval = 0
            for sample in categorySamples {
                totalMinutes += sample.endDate.timeIntervalSince(sample.startDate)
            }

            if totalMinutes > 0 {
                completion(self.formatValue(totalMinutes / 60.0))
            } else {
                completion(nil)
            }
        }

        healthStore.execute(query)
    }

    private func fetchHandwashing(startDate: Date, endDate: Date, completion: @escaping (String?) -> Void) {
        guard let handwashingType = HKCategoryType.categoryType(forIdentifier: .handwashingEvent) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: handwashingType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let categorySamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }

            var totalSeconds: TimeInterval = 0
            for sample in categorySamples {
                totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
            }

            if totalSeconds > 0 {
                completion(self.formatValue(totalSeconds))
            } else {
                completion(nil)
            }
        }

        healthStore.execute(query)
    }

    private func fetchToothbrushing(startDate: Date, endDate: Date, completion: @escaping (String?) -> Void) {
        guard let toothbrushingType = HKCategoryType.categoryType(forIdentifier: .toothbrushingEvent) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: toothbrushingType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let categorySamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }

            var totalSeconds: TimeInterval = 0
            for sample in categorySamples {
                totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
            }

            if totalSeconds > 0 {
                completion(self.formatValue(totalSeconds))
            } else {
                completion(nil)
            }
        }

        healthStore.execute(query)
    }

    private func fetchStandHours(startDate: Date, endDate: Date, completion: @escaping (String?) -> Void) {
        guard let standHourType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: standHourType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let categorySamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }

            var standCount = 0
            for sample in categorySamples {
                if sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
                    standCount += 1
                }
            }

            if standCount > 0 {
                completion("\(standCount)")
            } else {
                completion(nil)
            }
        }

        healthStore.execute(query)
    }

    private func fetchSexualActivity(startDate: Date, endDate: Date, completion: @escaping (String?, String?, String?) -> Void) {
        guard let sexualActivityType = HKCategoryType.categoryType(forIdentifier: .sexualActivity) else {
            completion(nil, nil, nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: sexualActivityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let categorySamples = samples as? [HKCategorySample] else {
                completion(nil, nil, nil)
                return
            }

            var unspecified = 0
            var protectionUsed = 0
            var protectionNotUsed = 0

            for sample in categorySamples {
                if let protectionUsedValue = sample.metadata?[HKMetadataKeySexualActivityProtectionUsed] as? Bool {
                    if protectionUsedValue {
                        protectionUsed += 1
                    } else {
                        protectionNotUsed += 1
                    }
                } else {
                    unspecified += 1
                }
            }

            completion(
                unspecified > 0 ? "\(unspecified)" : nil,
                protectionUsed > 0 ? "\(protectionUsed)" : nil,
                protectionNotUsed > 0 ? "\(protectionNotUsed)" : nil
            )
        }

        healthStore.execute(query)
    }

    private func formatValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(value)
        }
    }

    private func generateCSV(date: Date, data: [String: String]) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = timestampFormatter.string(from: Calendar.current.startOfDay(for: date))

        // Build header row
        let header = csvColumnOrder.joined(separator: ",")

        // Build data row
        var rowValues: [String] = []
        for column in csvColumnOrder {
            if column == "Date/Time" {
                rowValues.append(timestamp)
            } else {
                rowValues.append(data[column] ?? "")
            }
        }
        let dataRow = rowValues.joined(separator: ",")

        let csvContent = header + "\n" + dataRow + "\n"

        // Save to temporary directory
        let fileName = "HealthMetrics-\(dateString).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            print("CSV generated at: \(tempURL.path)")
            return tempURL
        } catch {
            print("Failed to write CSV: \(error.localizedDescription)")
            return nil
        }
    }
}
