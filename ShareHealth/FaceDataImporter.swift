import Foundation
import UIKit

/// Imports face captures from an export folder into the app's local storage
class FaceDataImporter: ObservableObject {

    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var currentFile: String = ""
    @Published var importedCount = 0
    @Published var skippedCount = 0
    @Published var errorCount = 0
    @Published var lastErrorReason: String = ""

    private let fileManager = FileManager.default
    private let dataStore = FacialDataStore.shared

    // Track error reasons for debugging
    private var errorReasons: [String: Int] = [:]

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: Int
        let message: String
        let errorDetails: String
    }

    /// Import face data from an export folder
    /// Expected structure: folder/faces/YYYY/MM/Face-*.jpg and Face-*.json
    func importFromFolder(url: URL, completion: @escaping (ImportResult) -> Void) {
        DispatchQueue.main.async {
            self.isImporting = true
            self.importProgress = 0
            self.importedCount = 0
            self.skippedCount = 0
            self.errorCount = 0
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Reset error tracking
            self.errorReasons = [:]

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                DispatchQueue.main.async {
                    self.isImporting = false
                    completion(ImportResult(imported: 0, skipped: 0, errors: 1, message: "Cannot access the selected folder", errorDetails: "Security access denied"))
                }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Find all Face-*.jpg files recursively
            var faceImages: [URL] = []
            self.findFaceImages(in: url, results: &faceImages)

            let totalFiles = faceImages.count
            if totalFiles == 0 {
                DispatchQueue.main.async {
                    self.isImporting = false
                    completion(ImportResult(imported: 0, skipped: 0, errors: 0, message: "No face images found in the selected folder", errorDetails: ""))
                }
                return
            }

            var imported = 0
            var skipped = 0
            var errors = 0

            for (index, imageURL) in faceImages.enumerated() {
                // Update progress on main thread and wait for it to complete
                // This ensures the UI updates are visible during import
                DispatchQueue.main.sync {
                    self.currentFile = imageURL.lastPathComponent
                    self.importProgress = Double(index) / Double(totalFiles)
                }

                let result = self.importFaceCapture(imageURL: imageURL)
                switch result {
                case .imported:
                    imported += 1
                case .skipped:
                    skipped += 1
                case .error(let reason):
                    errors += 1
                    self.errorReasons[reason, default: 0] += 1
                }

                // Update counts on main thread synchronously so UI reflects changes
                DispatchQueue.main.sync {
                    self.importedCount = imported
                    self.skippedCount = skipped
                    self.errorCount = errors
                    if case .error(let reason) = result {
                        self.lastErrorReason = reason
                    }
                }
            }

            // Build error details string
            let errorDetails = self.errorReasons.map { "\($0.key): \($0.value)" }.joined(separator: ", ")

            // Reload the data store and mark models as needing retraining
            self.dataStore.loadCaptures {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importProgress = 1.0

                    // Mark models as needing retraining if we imported any
                    if imported > 0 {
                        self.dataStore.dataVersion += 1
                        self.dataStore.modelsNeedRetraining = true
                    }

                    var message = "Imported \(imported) captures"
                    if skipped > 0 { message += ", skipped \(skipped) duplicates" }
                    if errors > 0 { message += ", \(errors) errors" }
                    if !errorDetails.isEmpty { message += "\n\nError details: \(errorDetails)" }

                    completion(ImportResult(imported: imported, skipped: skipped, errors: errors, message: message, errorDetails: errorDetails))
                }
            }
        }
    }

    private func findFaceImages(in directory: URL, results: inout [URL]) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                // Skip annotations and mediapipe directories - we handle them when finding metrics
                let dirName = item.lastPathComponent.lowercased()
                if dirName == "annotations" || dirName == "mediapipe" {
                    continue
                }
                // Recurse into subdirectories
                findFaceImages(in: item, results: &results)
            } else if item.lastPathComponent.hasPrefix("Face-") && item.pathExtension.lowercased() == "jpg" {
                results.append(item)
            }
        }
    }

    private enum ImportStatus {
        case imported
        case skipped
        case error(String)  // Include error reason
    }

    private func importFaceCapture(imageURL: URL) -> ImportStatus {
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        let directory = imageURL.deletingLastPathComponent()

        // Parse date from filename (Face-YYYY-MM-DD_HHMMSS)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "'Face-'yyyy-MM-dd_HHmmss"
        guard let captureDate = dateFormatter.date(from: baseName) else {
            print("Could not parse date from: \(baseName)")
            return .error("Invalid filename format")
        }

        // Check if already imported (by checking if file exists in local storage)
        let localDirectory = getLocalDirectory(for: captureDate)
        let localImageURL = localDirectory.appendingPathComponent("\(baseName).jpg")
        if fileManager.fileExists(atPath: localImageURL.path) {
            return .skipped
        }

        // Find metrics JSON in multiple possible locations:
        // 1. Same directory: Face-*.json
        // 2. annotations/mediapipe/Face-*.json (AI Steve pipeline)
        let metricsURL = findMetricsFile(baseName: baseName, imageDirectory: directory)

        // Load metrics if available
        var metrics: FacialMetrics? = nil
        if let metricsURL = metricsURL {
            metrics = try? FaceAnalysisCoordinator.loadMetrics(from: metricsURL)
            if metrics == nil {
                print("Failed to parse metrics from: \(metricsURL.lastPathComponent)")
            }
        } else {
            print("No metrics JSON found for: \(baseName), will analyze image")
        }

        // If no metrics JSON, try to analyze the image
        if metrics == nil {
            // Load the image and analyze it
            if let imageData = try? Data(contentsOf: imageURL),
               let image = UIImage(data: imageData) {
                let analyzer = MediaPipeFaceAnalyzer()
                let semaphore = DispatchSemaphore(value: 0)
                analyzer.analyze(image: image) { result in
                    metrics = result
                    semaphore.signal()
                }
                semaphore.wait()
            }
        }

        // If still no metrics, skip (we need metrics for model training)
        guard let metrics = metrics else {
            print("Could not analyze face in: \(baseName), skipping")
            return .error("No face detected in image")
        }

        // Find health data JSON in multiple possible locations
        let healthURL = findHealthDataFile(baseName: baseName, imageDirectory: directory)

        // Load health data if available
        var healthData: [String: String] = [:]
        if let healthURL = healthURL,
           let data = try? Data(contentsOf: healthURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            healthData = json
        }

        // Copy files directly to local storage (no re-encoding to preserve exact pixels)
        do {
            // Ensure local directory exists
            if !fileManager.fileExists(atPath: localDirectory.path) {
                try fileManager.createDirectory(at: localDirectory, withIntermediateDirectories: true)
            }

            // Copy image file directly (preserves exact pixels, no re-encoding)
            try fileManager.copyItem(at: imageURL, to: localImageURL)

            // Save metrics JSON
            let localMetricsURL = localDirectory.appendingPathComponent("\(baseName).json")
            try FaceAnalysisCoordinator.saveMetrics(metrics, to: localMetricsURL)

            // Save health data JSON
            let localHealthURL = localDirectory.appendingPathComponent("\(baseName)_health.json")
            let healthJSON = try JSONSerialization.data(withJSONObject: healthData, options: [.prettyPrinted, .sortedKeys])
            try healthJSON.write(to: localHealthURL)

            print("Imported face capture: \(baseName)")
            return .imported
        } catch {
            print("Failed to import \(baseName): \(error)")
            return .error("File copy failed: \(error.localizedDescription)")
        }
    }

    /// Find metrics JSON file in various possible locations
    private func findMetricsFile(baseName: String, imageDirectory: URL) -> URL? {
        // Build list of possible paths - check multiple directory levels
        var possiblePaths: [URL] = []

        // 1. Same directory as image: Face-*.json
        possiblePaths.append(imageDirectory.appendingPathComponent("\(baseName).json"))

        // 2. Subdirectories of image directory
        possiblePaths.append(imageDirectory.appendingPathComponent("annotations/mediapipe/\(baseName).json"))
        possiblePaths.append(imageDirectory.appendingPathComponent("mediapipe/\(baseName).json"))
        possiblePaths.append(imageDirectory.appendingPathComponent("annotations/\(baseName).json"))

        // 3. Go up directory levels and look for annotations folder
        // Structure might be: export/faces/YYYY/MM/image.jpg and export/annotations/mediapipe/image.json
        var parentDir = imageDirectory
        for _ in 0..<5 {  // Go up to 5 levels
            parentDir = parentDir.deletingLastPathComponent()
            possiblePaths.append(parentDir.appendingPathComponent("annotations/mediapipe/\(baseName).json"))
            possiblePaths.append(parentDir.appendingPathComponent("annotations/\(baseName).json"))
            possiblePaths.append(parentDir.appendingPathComponent("mediapipe/\(baseName).json"))
            possiblePaths.append(parentDir.appendingPathComponent("\(baseName).json"))
        }

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path) {
                print("Found metrics at: \(path.path)")
                return path
            }
        }

        // Debug: print what we looked for
        print("Could not find metrics for \(baseName) in any of \(possiblePaths.count) locations")
        print("Image directory: \(imageDirectory.path)")

        return nil
    }

    /// Find health data JSON file in various possible locations
    private func findHealthDataFile(baseName: String, imageDirectory: URL) -> URL? {
        // Possible locations for health data JSON:
        let possiblePaths = [
            // 1. Same directory as image: Face-*_health.json
            imageDirectory.appendingPathComponent("\(baseName)_health.json"),
            // 2. Just health.json in same directory
            imageDirectory.appendingPathComponent("\(baseName).health.json"),
        ]

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path) {
                return path
            }
        }

        return nil
    }

    private func getLocalDirectory(for date: Date) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let facesDir = documents.appendingPathComponent("faces", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        let yearMonth = formatter.string(from: date)
        return facesDir.appendingPathComponent(yearMonth, isDirectory: true)
    }
}
