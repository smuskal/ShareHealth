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

    private let fileManager = FileManager.default
    private let dataStore = FacialDataStore.shared

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: Int
        let message: String
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
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                DispatchQueue.main.async {
                    self.isImporting = false
                    completion(ImportResult(imported: 0, skipped: 0, errors: 1, message: "Cannot access the selected folder"))
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
                    completion(ImportResult(imported: 0, skipped: 0, errors: 0, message: "No face images found in the selected folder"))
                }
                return
            }

            var imported = 0
            var skipped = 0
            var errors = 0

            for (index, imageURL) in faceImages.enumerated() {
                DispatchQueue.main.async {
                    self.currentFile = imageURL.lastPathComponent
                    self.importProgress = Double(index) / Double(totalFiles)
                }

                let result = self.importFaceCapture(imageURL: imageURL)
                switch result {
                case .imported:
                    imported += 1
                case .skipped:
                    skipped += 1
                case .error:
                    errors += 1
                }

                DispatchQueue.main.async {
                    self.importedCount = imported
                    self.skippedCount = skipped
                    self.errorCount = errors
                }
            }

            // Reload the data store and mark models as needing retraining
            DispatchQueue.main.async {
                self.dataStore.loadCaptures()
                self.isImporting = false
                self.importProgress = 1.0

                // Mark models as needing retraining if we imported any
                if imported > 0 {
                    self.dataStore.dataVersion += 1
                    self.dataStore.modelsNeedRetraining = true
                }

                let message = "Imported \(imported) captures" +
                    (skipped > 0 ? ", skipped \(skipped) duplicates" : "") +
                    (errors > 0 ? ", \(errors) errors" : "")

                completion(ImportResult(imported: imported, skipped: skipped, errors: errors, message: message))
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
        case error
    }

    private func importFaceCapture(imageURL: URL) -> ImportStatus {
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        let directory = imageURL.deletingLastPathComponent()

        // Parse date from filename (Face-YYYY-MM-DD_HHMMSS)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "'Face-'yyyy-MM-dd_HHmmss"
        guard let captureDate = dateFormatter.date(from: baseName) else {
            print("Could not parse date from: \(baseName)")
            return .error
        }

        // Check if already imported (by checking if file exists in local storage)
        let localDirectory = getLocalDirectory(for: captureDate)
        let localImageURL = localDirectory.appendingPathComponent("\(baseName).jpg")
        if fileManager.fileExists(atPath: localImageURL.path) {
            return .skipped
        }

        // Load image - import exactly as saved (no transformation)
        guard let imageData = try? Data(contentsOf: imageURL),
              let image = UIImage(data: imageData) else {
            print("Could not load image: \(baseName)")
            return .error
        }

        // Find metrics JSON in multiple possible locations:
        // 1. Same directory: Face-*.json
        // 2. annotations/mediapipe/Face-*.json (AI Steve pipeline)
        let metricsURL = findMetricsFile(baseName: baseName, imageDirectory: directory)

        // Load metrics if available
        var metrics: FacialMetrics? = nil
        if let metricsURL = metricsURL {
            metrics = try? FaceAnalysisCoordinator.loadMetrics(from: metricsURL)
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

        // If no metrics, we need to analyze the image
        if metrics == nil {
            // For now, skip images without metrics
            // In a future version, we could re-analyze them
            print("No metrics found for: \(baseName), skipping")
            return .error
        }

        // Save to local storage
        do {
            try dataStore.saveCapture(
                image: image,
                metrics: metrics!,
                healthData: healthData,
                date: captureDate
            )
            return .imported
        } catch {
            print("Failed to save: \(error)")
            return .error
        }
    }

    /// Find metrics JSON file in various possible locations
    private func findMetricsFile(baseName: String, imageDirectory: URL) -> URL? {
        // Possible locations for metrics JSON:
        let possiblePaths = [
            // 1. Same directory as image: Face-*.json
            imageDirectory.appendingPathComponent("\(baseName).json"),
            // 2. annotations/mediapipe/ subdirectory (AI Steve pipeline)
            imageDirectory.appendingPathComponent("annotations/mediapipe/\(baseName).json"),
            // 3. Just mediapipe/ subdirectory
            imageDirectory.appendingPathComponent("mediapipe/\(baseName).json"),
        ]

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path) {
                return path
            }
        }

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
