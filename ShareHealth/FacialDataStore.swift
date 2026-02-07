import Foundation
import UIKit

/// Manages local storage of facial captures for on-device model building
class FacialDataStore: ObservableObject {

    static let shared = FacialDataStore()

    @Published var captures: [StoredFaceCapture] = []
    @Published var isLoading = false

    /// Increments whenever data changes - observe this to trigger retraining
    @Published var dataVersion: Int = 0

    /// Set when captures are added/deleted and models need retraining
    @Published var modelsNeedRetraining = false

    private let fileManager = FileManager.default

    private var facesDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("faces", isDirectory: true)
    }

    private init() {
        ensureDirectoryExists()
        loadCaptures()
    }

    // MARK: - Directory Management

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: facesDirectory.path) {
            try? fileManager.createDirectory(at: facesDirectory, withIntermediateDirectories: true)
        }
    }

    private func yearMonthDirectory(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        let yearMonth = formatter.string(from: date)
        return facesDirectory.appendingPathComponent(yearMonth, isDirectory: true)
    }

    // MARK: - Save Capture

    /// Save a face capture with its metrics and health data snapshot
    func saveCapture(
        image: UIImage,
        metrics: FacialMetrics,
        healthData: [String: String],
        date: Date = Date()
    ) throws {
        let directory = yearMonthDirectory(for: date)

        // Create directory if needed
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Generate timestamp-based filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: date)
        let baseFilename = "Face-\(timestamp)"

        // Save image
        let imageURL = directory.appendingPathComponent("\(baseFilename).jpg")
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw FacialDataStoreError.imageEncodingFailed
        }
        try imageData.write(to: imageURL)

        // Save metrics JSON
        let metricsURL = directory.appendingPathComponent("\(baseFilename).json")
        try FaceAnalysisCoordinator.saveMetrics(metrics, to: metricsURL)

        // Save health data snapshot
        let healthURL = directory.appendingPathComponent("\(baseFilename)_health.json")
        let healthJSON = try JSONSerialization.data(withJSONObject: healthData, options: [.prettyPrinted, .sortedKeys])
        try healthJSON.write(to: healthURL)

        print("Saved face capture locally: \(baseFilename)")

        // Reload captures list and mark models as needing retraining
        loadCaptures()
        DispatchQueue.main.async {
            self.dataVersion += 1
            self.modelsNeedRetraining = true
        }
    }

    // MARK: - Load Captures

    /// Load all stored captures
    func loadCaptures() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var allCaptures: [StoredFaceCapture] = []

            // Enumerate all year/month directories
            if let yearDirs = try? self.fileManager.contentsOfDirectory(at: self.facesDirectory, includingPropertiesForKeys: nil) {
                for yearDir in yearDirs {
                    if let monthDirs = try? self.fileManager.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: nil) {
                        for monthDir in monthDirs {
                            // Find all .jpg files
                            if let files = try? self.fileManager.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: [.creationDateKey]) {
                                let jpgFiles = files.filter { $0.pathExtension.lowercased() == "jpg" }

                                for jpgFile in jpgFiles {
                                    if let capture = self.loadCapture(from: jpgFile) {
                                        allCaptures.append(capture)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Sort by date, newest first
            allCaptures.sort { $0.captureDate > $1.captureDate }

            DispatchQueue.main.async {
                self.captures = allCaptures
                self.captureCount = allCaptures.count
                self.isLoading = false
            }
        }
    }

    private func loadCapture(from imageURL: URL) -> StoredFaceCapture? {
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        let directory = imageURL.deletingLastPathComponent()

        let metricsURL = directory.appendingPathComponent("\(baseName).json")
        let healthURL = directory.appendingPathComponent("\(baseName)_health.json")

        // Parse date from filename (Face-YYYY-MM-DD_HHMMSS)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "'Face-'yyyy-MM-dd_HHmmss"
        let captureDate = dateFormatter.date(from: baseName) ?? Date()

        // Load metrics if available
        var metrics: FacialMetrics? = nil
        if fileManager.fileExists(atPath: metricsURL.path) {
            metrics = try? FaceAnalysisCoordinator.loadMetrics(from: metricsURL)
        }

        // Load health data if available
        var healthData: [String: String]? = nil
        if fileManager.fileExists(atPath: healthURL.path),
           let data = try? Data(contentsOf: healthURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            healthData = json
        }

        return StoredFaceCapture(
            id: baseName,
            imageURL: imageURL,
            metricsURL: metricsURL,
            healthURL: healthURL,
            captureDate: captureDate,
            metrics: metrics,
            healthData: healthData
        )
    }

    // MARK: - Delete Captures

    /// Delete a single capture
    func deleteCapture(_ capture: StoredFaceCapture) throws {
        // Delete all associated files
        try? fileManager.removeItem(at: capture.imageURL)
        try? fileManager.removeItem(at: capture.metricsURL)
        try? fileManager.removeItem(at: capture.healthURL)

        // Reload and mark models as needing retraining
        loadCaptures()
        DispatchQueue.main.async {
            self.dataVersion += 1
            self.modelsNeedRetraining = true
        }
    }

    /// Delete all captures (purge)
    func purgeAllCaptures() throws {
        try fileManager.removeItem(at: facesDirectory)
        ensureDirectoryExists()

        DispatchQueue.main.async {
            self.captures = []
            self.captureCount = 0
        }
    }

    // MARK: - Statistics

    @Published var captureCount: Int = 0

    private func updateCaptureCount() {
        captureCount = captures.count
    }

    var oldestCapture: Date? {
        captures.last?.captureDate
    }

    var newestCapture: Date? {
        captures.first?.captureDate
    }

    /// Calculate storage size in bytes
    func calculateStorageSize() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: facesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    var formattedStorageSize: String {
        let bytes = calculateStorageSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Backfill Health Data

    @Published var isBackfilling = false
    @Published var backfillProgress: Double = 0
    @Published var backfilledCount = 0

    /// Count of captures missing health data
    var capturesMissingHealthData: Int {
        captures.filter { $0.healthData == nil || $0.healthData?.isEmpty == true }.count
    }

    /// Backfill health data from Apple Health for captures that don't have it
    func backfillHealthData(completion: @escaping (Int, Int) -> Void) {
        let capturesNeedingData = captures.filter { $0.healthData == nil || $0.healthData?.isEmpty == true }

        guard !capturesNeedingData.isEmpty else {
            completion(0, 0)
            return
        }

        DispatchQueue.main.async {
            self.isBackfilling = true
            self.backfillProgress = 0
            self.backfilledCount = 0
        }

        let exporter = HealthDataExporter()
        let total = capturesNeedingData.count
        var successCount = 0
        var errorCount = 0
        let queue = DispatchQueue(label: "backfill.serial")

        func processNext(index: Int) {
            guard index < capturesNeedingData.count else {
                // Done - reload captures and mark models as needing retraining
                DispatchQueue.main.async {
                    self.isBackfilling = false
                    self.backfillProgress = 1.0
                    self.loadCaptures()
                    if successCount > 0 {
                        self.dataVersion += 1
                        self.modelsNeedRetraining = true
                    }
                    completion(successCount, errorCount)
                }
                return
            }

            let capture = capturesNeedingData[index]

            DispatchQueue.main.async {
                self.backfillProgress = Double(index) / Double(total)
            }

            exporter.exportHealthDataRaw(for: capture.captureDate) { healthData in
                queue.async {
                    if let healthData = healthData, !healthData.isEmpty {
                        // Save health data JSON
                        do {
                            let healthJSON = try JSONSerialization.data(withJSONObject: healthData, options: [.prettyPrinted, .sortedKeys])
                            try healthJSON.write(to: capture.healthURL)
                            successCount += 1
                            DispatchQueue.main.async {
                                self.backfilledCount = successCount
                            }
                        } catch {
                            print("Failed to save health data for \(capture.id): \(error)")
                            errorCount += 1
                        }
                    } else {
                        print("No health data available for \(capture.captureDate)")
                        errorCount += 1
                    }

                    // Process next capture
                    processNext(index: index + 1)
                }
            }
        }

        // Start processing
        processNext(index: 0)
    }

    /// Update health data for a single capture
    func updateHealthData(for capture: StoredFaceCapture, healthData: [String: String]) throws {
        let healthJSON = try JSONSerialization.data(withJSONObject: healthData, options: [.prettyPrinted, .sortedKeys])
        try healthJSON.write(to: capture.healthURL)
    }
}

// MARK: - Data Models

struct StoredFaceCapture: Identifiable {
    let id: String
    let imageURL: URL
    let metricsURL: URL
    let healthURL: URL
    let captureDate: Date
    let metrics: FacialMetrics?
    let healthData: [String: String]?

    var hasMetrics: Bool { metrics != nil }
    var hasHealthData: Bool { healthData != nil }

    func loadImage() -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Errors

enum FacialDataStoreError: LocalizedError {
    case imageEncodingFailed
    case directoryCreationFailed
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode image"
        case .directoryCreationFailed:
            return "Failed to create storage directory"
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Image Utilities

extension UIImage {
    /// Flip the image horizontally by transforming actual pixel data.
    /// This creates a new image with flipped pixels, not just orientation metadata.
    func flippedHorizontally() -> UIImage {
        // Get the actual rendered size (accounting for orientation)
        let imageSize = self.size

        // Create a graphics context and draw the flipped image
        UIGraphicsBeginImageContextWithOptions(imageSize, false, self.scale)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else {
            return self
        }

        // Apply horizontal flip transform
        context.translateBy(x: imageSize.width, y: 0)
        context.scaleBy(x: -1.0, y: 1.0)

        // Draw the original image (this renders pixels with the transform applied)
        self.draw(in: CGRect(origin: .zero, size: imageSize))

        // Get the new image with transformed pixels
        guard let flippedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            return self
        }

        return flippedImage
    }
}
