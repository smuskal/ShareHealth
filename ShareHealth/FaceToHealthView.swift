import SwiftUI
import UIKit
import HealthKit
import PhotosUI
import Photos

/// Main view for Face-to-Health prediction feature
struct FaceToHealthView: View {
    @StateObject private var viewModel = FaceToHealthViewModel()
    @StateObject private var importer = FaceDataImporter()
    @ObservedObject private var dataStore = FacialDataStore.shared

    @State private var showingFaceCapture = false
    @State private var showingFaceHistory = false
    @State private var showingModelDetails = false
    @State private var showingImportPicker = false
    @State private var showingImportResult = false
    @State private var importResultMessage = ""
    @State private var showingPredictionMode = false
    @State private var showingBackfillResult = false
    @State private var backfillResultMessage = ""
    @State private var selectedModelForDetail: ModelDetailSelection? = nil
    @State private var showingAddTarget = false

    // Photo import
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false
    @State private var photoImportProgress: Double = 0
    @State private var photoImportStatus: String = ""
    @State private var showingPhotoPicker = false
    @State private var isAutoBackfilling = false  // Tracks auto-backfill after import

    // Expanded image view
    @State private var expandedImage: UIImage? = nil
    @State private var showingExpandedImage = false

    // Model snapshots
    @State private var showingSnapshotManager = false
    @State private var showingSaveSnapshot = false
    @State private var snapshotName = ""
    @State private var showingSnapshotResult = false
    @State private var snapshotResultMessage = ""

    // Model type selection
    @State private var selectedModelType: ModelType = FaceHealthModelTrainer.currentModelType

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    captureSection

                    if importer.isImporting {
                        importProgressSection
                    }

                    if isImportingPhotos {
                        photoImportProgressSection
                    }

                    if dataStore.isBackfilling {
                        backfillProgressSection
                    }

                    // Show warning if captures are missing health data (hide during auto-backfill)
                    if dataStore.capturesMissingHealthData > 0 && !dataStore.isBackfilling && !isAutoBackfilling {
                        missingHealthDataSection
                    }

                    modelTargetsSection
                    dataStatusSection

                    // Model snapshots section (show if any models are trained)
                    if viewModel.hasAnyModel {
                        modelSnapshotsSection
                    }

                    // Show prediction button when model is ready - at top of predictions card
                    if viewModel.hasAnyModel {
                        predictNowSection
                    }

                    // Only show predictions after user explicitly does "Predict My Health Now"
                    if viewModel.hasMadePrediction && (viewModel.hasAnyModel || dataStore.captureCount >= 14) {
                        predictionSection
                    }
                }
                .padding()
            }
            .navigationTitle("Face to Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingImportPicker = true }) {
                            Label("Import from Export Folder", systemImage: "folder")
                        }

                        Button(action: {
                            // Clear any previous selections before showing picker
                            selectedPhotos = []
                            showingPhotoPicker = true
                        }) {
                            Label("Import from Photos", systemImage: "photo.on.rectangle")
                        }

                        if dataStore.capturesMissingHealthData > 0 {
                            Button(action: { startBackfill() }) {
                                Label("Backfill Health Data (\(dataStore.capturesMissingHealthData))", systemImage: "heart.text.square")
                            }
                        }

                        Divider()

                        Button(action: { viewModel.retrainAllModels() }) {
                            Label("Retrain Models", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                viewModel.checkAvailableTargets()
                dataStore.loadCaptures()
                viewModel.updateAllPredictions()
                // Auto-retrain models once data is loaded
                viewModel.retrainWhenReady()
            }
            .onChange(of: selectedPhotos) { _, newItems in
                if !newItems.isEmpty {
                    importPhotosFromLibrary(items: newItems)
                    selectedPhotos = []
                }
            }
            .onChange(of: dataStore.modelsNeedRetraining) { _, needsRetrain in
                if needsRetrain && !viewModel.isTraining {
                    // Auto-retrain when data changes
                    dataStore.modelsNeedRetraining = false
                    viewModel.retrainAllModels()
                }
            }
            .fullScreenCover(isPresented: $showingFaceCapture) {
                StandaloneFaceCaptureView(
                    onCapture: { image, metrics in
                        viewModel.handleCapture(image: image, metrics: metrics)
                    },
                    onCancel: { }
                )
            }
            .fullScreenCover(isPresented: $showingPredictionMode) {
                PredictionCaptureView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingFaceHistory) {
                FaceHistoryView()
            }
            .sheet(isPresented: $showingImportPicker) {
                ImportFolderPickerView { url in
                    showingImportPicker = false
                    if let url = url {
                        importer.importFromFolder(url: url) { result in
                            importResultMessage = result.message
                            showingImportResult = true
                            // Retraining will happen automatically via dataStore.modelsNeedRetraining
                        }
                    }
                }
            }
            .alert("Import Complete", isPresented: $showingImportResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importResultMessage)
            }
            .alert("Backfill Complete", isPresented: $showingBackfillResult) {
                Button("OK", role: .cancel) {
                    // Retrain models after backfill
                    viewModel.retrainAllModels()
                }
            } message: {
                Text(backfillResultMessage)
            }
            .sheet(item: $selectedModelForDetail) { selection in
                ModelCVDetailView(
                    targetId: selection.targetId,
                    targetName: selection.targetName,
                    captures: dataStore.captures
                )
            }
            .sheet(isPresented: $showingAddTarget) {
                AddCustomTargetView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotosPickerSheet(selectedPhotos: $selectedPhotos)
            }
            .sheet(isPresented: $showingSnapshotManager) {
                ModelSnapshotManagerView(viewModel: viewModel) { message in
                    snapshotResultMessage = message
                    showingSnapshotResult = true
                }
            }
            .fullScreenCover(isPresented: $showingExpandedImage) {
                ExpandedImageView(image: expandedImage) {
                    showingExpandedImage = false
                    expandedImage = nil
                }
            }
            .alert("Save Model Snapshot", isPresented: $showingSaveSnapshot) {
                TextField("Snapshot Name", text: $snapshotName)
                Button("Cancel", role: .cancel) {
                    snapshotName = ""
                }
                Button("Save") {
                    saveModelSnapshot()
                }
                .disabled(snapshotName.isEmpty)
            } message: {
                Text("Enter a name for this snapshot")
            }
            .alert("Snapshot", isPresented: $showingSnapshotResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(snapshotResultMessage)
            }
        }
    }

    private func saveModelSnapshot() {
        guard !snapshotName.isEmpty else { return }
        let trainer = FaceHealthModelTrainer()
        let targetIds = Array(viewModel.selectedTargets)

        do {
            try trainer.saveSnapshot(name: snapshotName, targetIds: targetIds)
            snapshotResultMessage = "Snapshot '\(snapshotName)' saved with \(targetIds.count) models"
            snapshotName = ""
            showingSnapshotResult = true
        } catch {
            snapshotResultMessage = "Failed to save: \(error.localizedDescription)"
            showingSnapshotResult = true
        }
    }

    // MARK: - Backfill

    private func startBackfill() {
        dataStore.backfillHealthData { success, errors in
            backfillResultMessage = "Backfilled \(success) captures" +
                (errors > 0 ? ", \(errors) without health data" : "")
            showingBackfillResult = true
        }
    }

    // MARK: - Missing Health Data Section

    private var missingHealthDataSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Health Data Missing")
                    .font(.headline)
                Spacer()
            }

            Text("\(dataStore.capturesMissingHealthData) captures don't have health data from Apple Health. Backfill to enable model training.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { startBackfill() }) {
                HStack {
                    Image(systemName: "heart.text.square")
                    Text("Backfill from Apple Health")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Backfill Progress

    private var backfillProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                Text("Backfilling Health Data...")
                    .font(.headline)
            }

            ProgressView(value: dataStore.backfillProgress)
                .tint(.orange)

            Text("\(dataStore.backfilledCount) captures updated")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Import Progress

    private var importProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                Text("Importing from folder...")
                    .font(.headline)
            }

            ProgressView(value: importer.importProgress)
                .tint(.purple)

            Text(importer.currentFile)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 20) {
                Label("\(importer.importedCount)", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                Label("\(importer.skippedCount)", systemImage: "arrow.right.circle")
                    .foregroundColor(.orange)
                Label("\(importer.errorCount)", systemImage: "xmark.circle")
                    .foregroundColor(.red)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }

    private var photoImportProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                Text("Importing from Photos...")
                    .font(.headline)
            }

            ProgressView(value: photoImportProgress)
                .tint(.green)

            Text(photoImportStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private func importPhotosFromLibrary(items: [PhotosPickerItem]) {
        isImportingPhotos = true
        photoImportProgress = 0
        photoImportStatus = "Starting import..."

        let analyzer = MediaPipeFaceAnalyzer()
        let total = items.count
        var imported = 0
        var failed = 0

        Task {
            for (index, item) in items.enumerated() {
                await MainActor.run {
                    photoImportProgress = Double(index) / Double(total)
                    photoImportStatus = "Processing photo \(index + 1) of \(total)..."
                }

                // Load the image data - import exactly as saved (no transformation)
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    failed += 1
                    continue
                }

                // Get the photo's creation date if available
                let photoDate = await getPhotoDate(for: item) ?? Date()

                // Analyze with MediaPipe (use the corrected image)
                let metrics = await withCheckedContinuation { continuation in
                    analyzer.analyze(image: image) { result in
                        continuation.resume(returning: result)
                    }
                }

                guard let metrics = metrics else {
                    failed += 1
                    await MainActor.run {
                        photoImportStatus = "No face detected in photo \(index + 1)"
                    }
                    continue
                }

                // Save to FacialDataStore (no health data - will need backfill)
                do {
                    try FacialDataStore.shared.saveCapture(
                        image: image,
                        metrics: metrics,
                        healthData: [:],  // Empty - needs backfill
                        date: photoDate
                    )
                    imported += 1
                } catch {
                    failed += 1
                }
            }

            await MainActor.run {
                isImportingPhotos = false
                photoImportProgress = 1.0

                // Auto-backfill if we imported photos, then show one consolidated message
                if imported > 0 {
                    autoBackfillAndRetrain(imported: imported, failed: failed)
                } else {
                    // No imports - just show the failure message
                    let message = "Import complete: \(failed) failed (no face detected)"
                    importResultMessage = message
                    showingImportResult = true
                }
            }
        }
    }

    /// Automatically backfill health data and retrain models after import
    /// Shows a single consolidated message at the end
    private func autoBackfillAndRetrain(imported: Int = 0, failed: Int = 0) {
        // Mark that auto-backfill is starting
        isAutoBackfilling = true

        guard dataStore.capturesMissingHealthData > 0 else {
            // No backfill needed, just retrain and show result
            isAutoBackfilling = false
            viewModel.retrainAllModels()

            // Show consolidated message
            var message = "Imported \(imported) photos"
            if failed > 0 {
                message += ", \(failed) failed"
            }
            message += ". Models retrained."
            importResultMessage = message
            showingImportResult = true
            return
        }

        dataStore.backfillHealthData { success, errors in
            DispatchQueue.main.async {
                // Auto-backfill is complete
                self.isAutoBackfilling = false

                // Retrain models
                self.viewModel.retrainAllModels()

                // Show ONE consolidated message
                var message = "Imported \(imported) photos"
                if failed > 0 {
                    message += ", \(failed) failed"
                }
                message += ". Backfilled \(success) with health data"
                if errors > 0 {
                    message += " (\(errors) missing)"
                }
                message += ". Models retrained."
                self.importResultMessage = message
                self.showingImportResult = true
            }
        }
    }

    private func getPhotoDate(for item: PhotosPickerItem) async -> Date? {
        // Use the item identifier to fetch the PHAsset and get its creation date
        guard let identifier = item.itemIdentifier else { return nil }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        return asset.creationDate
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("Predict Health from Your Face")
                .font(.headline)

            Text("Train personalized models to predict health metrics from facial analysis")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Capture Section

    private var captureSection: some View {
        VStack(spacing: 12) {
            Button(action: { showingFaceCapture = true }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Capture Face")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)

            Button(action: { showingFaceHistory = true }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("View History")
                    Spacer()
                    Text("\(dataStore.captureCount) captures")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // MARK: - Model Targets Section

    private var modelTargetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prediction Targets")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.availableTargets.count + viewModel.unavailableTargets.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { showingAddTarget = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
            }

            // Scrollable list of targets with max height
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.availableTargets) { target in
                        let isUserAdded = viewModel.customTargets.contains { $0.id == target.id }
                        ModelTargetRow(
                            target: target,
                            isSelected: viewModel.selectedTargets.contains(target.id),
                            onToggle: { viewModel.toggleTarget(target.id) },
                            onDelete: isUserAdded ? { viewModel.removeCustomTarget(target.id) } : nil
                        )
                    }

                    if viewModel.unavailableTargets.count > 0 {
                        Text("Unavailable (insufficient data)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)

                        ForEach(viewModel.unavailableTargets) { target in
                            let isUserAdded = viewModel.customTargets.contains { $0.id == target.id }
                            UnavailableTargetRow(
                                target: target,
                                onDelete: isUserAdded ? { viewModel.removeCustomTarget(target.id) } : nil
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 300)  // Limit height to prevent excessive expansion
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Data Status Section

    private var dataStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Training Data")
                    .font(.headline)
                Spacer()
                Text("\(dataStore.captureCount) samples")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Progress towards minimum data
            let minSamples = 14
            let progress = min(Double(dataStore.captureCount) / Double(minSamples), 1.0)

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .green : .orange)

                if dataStore.captureCount < minSamples {
                    Text("\(minSamples - dataStore.captureCount) more captures needed for reliable predictions")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Sufficient data for model training")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Training progress
            if viewModel.isTraining {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.trainingProgress)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }

            // Model type selection
            HStack {
                Text("Model Type")
                    .font(.subheadline)
                Spacer()
                Picker("Model Type", selection: $selectedModelType) {
                    ForEach(ModelType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModelType) { _, newValue in
                    FaceHealthModelTrainer.currentModelType = newValue
                    // Retrain models with new type
                    if !viewModel.isTraining {
                        viewModel.retrainAllModels()
                    }
                }
            }
            .padding(.vertical, 4)

            // Model status for each selected target
            HStack {
                Text("Model Status (LOO-CV)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.isTraining {
                    Text("Tap to train or view details")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 4)

            // Scrollable model status list, sorted by R value (best first)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(sortedSelectedTargets, id: \.self) { targetId in
                        if let status = viewModel.modelStatus[targetId] {
                            ModelStatusRow(
                                targetId: targetId,
                                targetName: viewModel.targetName(for: targetId),
                                status: status,
                                timingNote: timingNote(for: targetId),
                                sampleCount: getSampleCount(for: targetId),
                                onTap: {
                                    // Only allow tap if not training
                                    guard !viewModel.isTraining else { return }
                                    switch status {
                                    case .trained:
                                        // Show model details
                                        selectedModelForDetail = ModelDetailSelection(
                                            targetId: targetId,
                                            targetName: viewModel.targetName(for: targetId)
                                        )
                                    case .notTrained, .failed:
                                        // Trigger retraining
                                        viewModel.retrainAllModels()
                                    case .training:
                                        break // Already training
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 200)  // Limit height to make it scrollable
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    /// Returns selected targets sorted by R value (highest first)
    private var sortedSelectedTargets: [String] {
        Array(viewModel.selectedTargets).sorted { id1, id2 in
            let r1 = correlationValue(for: id1)
            let r2 = correlationValue(for: id2)
            return r1 > r2  // Sort descending (best first)
        }
    }

    /// Get sample count for a specific target
    private func getSampleCount(for targetId: String) -> Int {
        let trainer = FaceHealthModelTrainer()
        return trainer.getSampleCount(for: targetId, captures: dataStore.captures)
    }

    private func correlationValue(for targetId: String) -> Double {
        if let status = viewModel.modelStatus[targetId],
           case .trained(let correlation) = status {
            return correlation
        }
        return -1  // Put untrained models last
    }

    /// Returns timing note for prediction target (current vs forward-looking)
    private func timingNote(for targetId: String) -> String? {
        switch targetId {
        case "sleepScore":
            return "Last Night"  // Reflects most recent sleep
        case "hrv", "restingHR":
            return "Today"  // Reflects current state
        default:
            // For custom targets, most health metrics are current-day
            return "Today"
        }
    }

    // MARK: - Model Snapshots Section

    private var modelSnapshotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Snapshots")
                    .font(.headline)
                Spacer()
            }

            Text("Save your trained models to restore later")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button(action: { showingSaveSnapshot = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Models")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button(action: { showingSnapshotManager = true }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Restore")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Prediction Section

    private var predictionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Predictions")
                    .font(.headline)
                Spacer()
                if let latestCapture = dataStore.captures.first {
                    Text(formatPredictionDate(latestCapture.captureDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let latestCapture = dataStore.captures.first {
                // Show face thumbnail with predictions
                HStack(alignment: .top, spacing: 16) {
                    // Face image thumbnail - tappable to expand
                    if let image = latestCapture.loadImage() {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                // Small expand icon
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                }
                                .padding(4)
                            )
                            .onTapGesture {
                                expandedImage = image
                                showingExpandedImage = true
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Image(systemName: "face.smiling")
                                    .foregroundColor(.gray)
                            )
                    }

                    // Predictions list
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedPredictionTargets, id: \.self) { targetId in
                            if let prediction = viewModel.predictions[targetId] {
                                PredictionRow(
                                    targetId: targetId,
                                    targetName: viewModel.targetName(for: targetId),
                                    prediction: prediction,
                                    confidence: getModelConfidence(for: targetId)
                                )
                            }
                        }
                    }
                }

                // Small face icon with date at bottom
                HStack {
                    Image(systemName: "face.smiling")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Based on capture from \(formatFullDate(latestCapture.captureDate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            } else {
                Text("Capture a face to see predictions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    /// Get model confidence (R value) for a target
    private func getModelConfidence(for targetId: String) -> Double? {
        if let status = viewModel.modelStatus[targetId],
           case .trained(let correlation) = status {
            return correlation
        }
        return nil
    }

    /// Returns selected targets sorted by R value (highest first) for predictions
    private var sortedPredictionTargets: [String] {
        Array(viewModel.selectedTargets).sorted { id1, id2 in
            let r1 = getModelConfidence(for: id1) ?? -1
            let r2 = getModelConfidence(for: id2) ?? -1
            return r1 > r2
        }
    }

    private func formatPredictionDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Predict Now Section (shown above predictions)

    private var predictNowSection: some View {
        Button(action: { showingPredictionMode = true }) {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Predict My Health Now")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .controlSize(.large)
    }
}

// MARK: - Model Target Row

private struct ModelTargetRow: View {
    let target: PredictionTarget
    let isSelected: Bool
    let onToggle: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: target.icon)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(target.description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding()
            .background(isSelected ? Color.blue : Color(.systemBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove Target", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Unavailable Target Row

private struct UnavailableTargetRow: View {
    let target: PredictionTarget
    let onDelete: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: target.icon)
                .foregroundColor(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Not enough data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .foregroundColor(.red)
                }
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray5))
        .cornerRadius(10)
        .opacity(0.6)
    }
}

// MARK: - Model Status Row

private struct ModelStatusRow: View {
    let targetId: String
    let targetName: String
    let status: ModelTrainingStatus
    let timingNote: String?
    let sampleCount: Int  // Number of valid samples for this target
    let requiredSamples: Int = 7  // Minimum required
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(targetName)
                        .font(.caption)
                        .fontWeight(.medium)

                    if let timing = timingNote {
                        Text("Predicts: \(timing)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                switch status {
                case .notTrained:
                    if sampleCount < requiredSamples {
                        // Show sample count when not enough data
                        HStack(spacing: 4) {
                            Text("\(sampleCount)/\(requiredSamples) samples")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else {
                        // Enough samples, show tap to train
                        HStack(spacing: 4) {
                            Text("Tap to train")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Image(systemName: "play.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                case .training:
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Training...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                case .trained(let correlation):
                    HStack(spacing: 4) {
                        if correlation < 0.3 {
                            Text(String(format: "R=%.2f", correlation))
                                .font(.caption)
                                .foregroundColor(.orange)
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text(String(format: "R=%.2f", correlation))
                                .font(.caption)
                                .foregroundColor(.green)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                case .failed(let errorMessage):
                    // Show sample count and error info
                    if sampleCount < requiredSamples {
                        HStack(spacing: 4) {
                            Text("\(sampleCount)/\(requiredSamples) days")
                                .font(.caption)
                                .foregroundColor(.red)
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else if errorMessage.contains("singular") {
                        // Matrix singular error - usually means features are too correlated
                        HStack(spacing: 4) {
                            Text("Data issue")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .help("Training failed: \(errorMessage)")
                    } else {
                        // Enough samples, show tap to retry
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Tap to retry")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Image(systemName: "arrow.clockwise.circle")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Text(errorMessage)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prediction Row

private struct PredictionRow: View {
    let targetId: String
    let targetName: String
    let prediction: Double
    let confidence: Double?  // Model R value

    var body: some View {
        HStack {
            // Icon for the target
            Image(systemName: iconForTarget(targetId))
                .foregroundColor(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(targetName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Confidence indicator
                if let conf = confidence {
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", conf * 100))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(confidenceColor(conf))
                    }
                }
            }

            Spacer()

            Text(formatPrediction(prediction, for: targetId))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(colorForPrediction(prediction, targetId: targetId))
        }
        .padding(.vertical, 4)
    }

    private func iconForTarget(_ targetId: String) -> String {
        switch targetId {
        case "sleepScore": return "bed.double.fill"
        case "hrv": return "waveform.path.ecg"
        case "restingHR": return "heart.fill"
        default: return "chart.line.uptrend.xyaxis"
        }
    }

    private func confidenceColor(_ value: Double) -> Color {
        if value >= 0.5 {
            return .green
        } else if value >= 0.3 {
            return .orange
        } else {
            return .red
        }
    }

    private func formatPrediction(_ value: Double, for targetId: String) -> String {
        switch targetId {
        case "sleepScore":
            return String(format: "%.0f", max(0, min(100, value)))
        case "hrv":
            return String(format: "%.0f ms", max(0, value))
        case "restingHR":
            return String(format: "%.0f bpm", max(0, value))
        default:
            return String(format: "%.1f", value)
        }
    }

    private func colorForPrediction(_ value: Double, targetId: String) -> Color {
        switch targetId {
        case "sleepScore":
            return value >= 70 ? .green : (value >= 50 ? .orange : .red)
        case "hrv":
            return value >= 50 ? .green : (value >= 30 ? .orange : .red)
        case "restingHR":
            return value <= 60 ? .green : (value <= 80 ? .orange : .red)
        default:
            return .primary
        }
    }
}

// MARK: - Standalone Face Capture View

struct StandaloneFaceCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var analysisCoordinator = FaceAnalysisCoordinator()
    @StateObject private var exporter = HealthDataExporter()

    let onCapture: (UIImage, FacialMetrics?) -> Void
    let onCancel: () -> Void

    @State private var showingCamera = true

    var body: some View {
        FaceCaptureView(
            onCapture: { image, metrics in
                // Save locally with health data
                saveLocally(image: image, metrics: metrics)
                onCapture(image, metrics)
                dismiss()
            },
            onCancel: {
                onCancel()
                dismiss()
            }
        )
    }

    private func saveLocally(image: UIImage, metrics: FacialMetrics?) {
        guard let metrics = metrics else { return }

        // Get today's health data and save
        exporter.exportHealthDataRaw(for: Date()) { healthData in
            DispatchQueue.main.async {
                do {
                    try FacialDataStore.shared.saveCapture(
                        image: image,
                        metrics: metrics,
                        healthData: healthData ?? [:],
                        date: Date()
                    )
                } catch {
                    print("Failed to save capture: \(error)")
                }
            }
        }
    }
}

// MARK: - View Model

class FaceToHealthViewModel: ObservableObject {
    @Published var availableTargets: [PredictionTarget] = []
    @Published var unavailableTargets: [PredictionTarget] = []
    @Published var selectedTargets: Set<String> = []
    @Published var modelStatus: [String: ModelTrainingStatus] = [:]
    @Published var predictions: [String: Double] = [:]
    @Published var isTraining = false
    @Published var trainingProgress: String = ""
    @Published var hasMadePrediction = false  // True only after explicit "Predict My Health Now"

    private let healthStore = HKHealthStore()
    private let modelTrainer = FaceHealthModelTrainer()
    private var trainingTargetsRemaining = 0

    var hasAnyModel: Bool {
        modelStatus.values.contains { if case .trained = $0 { return true } else { return false } }
    }

    var isAnyModelTraining: Bool {
        modelStatus.values.contains { if case .training = $0 { return true } else { return false } }
    }

    init() {
        loadSavedTargets()
        loadCustomTargets()
    }

    func checkAvailableTargets() {
        // Combine built-in targets with custom targets
        let allTargets = PredictionTarget.allTargets + customTargets

        // Check which targets have data
        let group = DispatchGroup()
        var available: [PredictionTarget] = []
        var unavailable: [PredictionTarget] = []

        for target in allTargets {
            group.enter()
            checkDataAvailability(for: target) { hasData in
                if hasData {
                    available.append(target)
                } else {
                    unavailable.append(target)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.availableTargets = available.sorted { $0.name < $1.name }
            self.unavailableTargets = unavailable.sorted { $0.name < $1.name }

            // Update model status for selected targets
            for targetId in self.selectedTargets {
                self.updateModelStatus(for: targetId)
            }
        }
    }

    private func checkDataAvailability(for target: PredictionTarget, completion: @escaping (Bool) -> Void) {
        switch target.id {
        case "sleepScore":
            // Sleep data is always available if they have sleep records
            checkSleepDataAvailable(completion: completion)
        case "hrv":
            checkQuantityDataAvailable(identifier: .heartRateVariabilitySDNN, completion: completion)
        case "restingHR":
            checkQuantityDataAvailable(identifier: .restingHeartRate, completion: completion)
        default:
            // For custom targets, check if we have data in stored captures
            checkCustomTargetDataAvailable(healthKey: target.id, completion: completion)
        }
    }

    private func checkCustomTargetDataAvailable(healthKey: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let captures = FacialDataStore.shared.captures
            var count = 0

            for capture in captures {
                guard let healthData = capture.healthData,
                      let value = healthData[healthKey],
                      Double(value) != nil else { continue }
                count += 1
            }

            DispatchQueue.main.async {
                // Need at least a few samples to be useful
                completion(count >= 3)
            }
        }
    }

    private func checkSleepDataAvailable(completion: @escaping (Bool) -> Void) {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(false)
            return
        }

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: nil,
            limit: 1,
            sortDescriptors: nil
        ) { _, samples, _ in
            DispatchQueue.main.async {
                completion((samples?.count ?? 0) > 0)
            }
        }

        healthStore.execute(query)
    }

    private func checkQuantityDataAvailable(identifier: HKQuantityTypeIdentifier, completion: @escaping (Bool) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(false)
            return
        }

        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: nil,
            limit: 1,
            sortDescriptors: nil
        ) { _, samples, _ in
            DispatchQueue.main.async {
                completion((samples?.count ?? 0) > 0)
            }
        }

        healthStore.execute(query)
    }

    func toggleTarget(_ targetId: String) {
        if selectedTargets.contains(targetId) {
            selectedTargets.remove(targetId)
        } else {
            selectedTargets.insert(targetId)
            updateModelStatus(for: targetId)
        }
        saveSelectedTargets()
    }

    private func updateModelStatus(for targetId: String) {
        // Check if we have a trained model
        if let correlation = modelTrainer.getModelCorrelation(for: targetId) {
            modelStatus[targetId] = .trained(correlation: correlation)
        } else {
            modelStatus[targetId] = .notTrained
        }
    }

    func handleCapture(image: UIImage, metrics: FacialMetrics?) {
        // Model retraining will be triggered automatically via the dataStore.modelsNeedRetraining
        // flag which is set when the capture is saved. No need to train here.
        // Just update predictions after a delay to reflect new data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateAllPredictions()
        }
    }

    private func trainModel(for targetId: String) {
        modelStatus[targetId] = .training

        modelTrainer.train(for: targetId, captures: FacialDataStore.shared.captures) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let correlation):
                    self?.modelStatus[targetId] = .trained(correlation: correlation)
                    self?.updatePrediction(for: targetId)
                case .failure(let error):
                    self?.modelStatus[targetId] = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func updatePrediction(for targetId: String) {
        guard let latestCapture = FacialDataStore.shared.captures.first,
              let metrics = latestCapture.metrics else { return }

        if let prediction = modelTrainer.predict(for: targetId, metrics: metrics) {
            predictions[targetId] = prediction
        }
    }

    private func loadSavedTargets() {
        if let saved = UserDefaults.standard.array(forKey: "selectedPredictionTargets") as? [String] {
            selectedTargets = Set(saved)
        }
    }

    private func saveSelectedTargets() {
        UserDefaults.standard.set(Array(selectedTargets), forKey: "selectedPredictionTargets")
    }

    func retrainAllModels() {
        let captureCount = FacialDataStore.shared.captureCount

        // If not enough data, clear all models and predictions
        guard captureCount >= 7 else {
            clearModelsAndPredictions()
            return
        }
        guard !selectedTargets.isEmpty else { return }

        isTraining = true
        trainingTargetsRemaining = selectedTargets.count
        trainingProgress = "Training 0/\(selectedTargets.count)..."

        var completed = 0
        let total = selectedTargets.count

        for targetId in selectedTargets {
            trainModelWithProgress(for: targetId) { [weak self] in
                completed += 1
                DispatchQueue.main.async {
                    self?.trainingProgress = "Training \(completed)/\(total)..."
                    if completed >= total {
                        self?.isTraining = false
                        self?.trainingProgress = ""
                    }
                }
            }
        }
    }

    /// Clear all models and predictions when data is insufficient
    private func clearModelsAndPredictions() {
        // Clear predictions
        predictions.removeAll()

        // Reset model status for all targets
        for targetId in selectedTargets {
            modelStatus[targetId] = .notTrained
        }

        // Delete saved models
        let trainer = FaceHealthModelTrainer()
        trainer.deleteAllModels()
    }

    /// Wait for data to load, then auto-retrain models
    func retrainWhenReady() {
        let dataStore = FacialDataStore.shared

        // If still loading, wait and retry
        if dataStore.isLoading {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.retrainWhenReady()
            }
            return
        }

        // If not enough data, skip
        guard dataStore.captureCount >= 7 else { return }
        guard !selectedTargets.isEmpty else { return }

        // Don't retrain if already training
        guard !isTraining else { return }

        // Retrain all models
        retrainAllModels()
    }

    private func trainModelWithProgress(for targetId: String, completion: @escaping () -> Void) {
        modelStatus[targetId] = .training

        modelTrainer.train(for: targetId, captures: FacialDataStore.shared.captures) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let correlation):
                    self?.modelStatus[targetId] = .trained(correlation: correlation)
                    self?.updatePrediction(for: targetId)
                case .failure(let error):
                    self?.modelStatus[targetId] = .failed(error.localizedDescription)
                }
                completion()
            }
        }
    }

    func updateAllPredictions() {
        for targetId in selectedTargets {
            updateModelStatus(for: targetId)
            updatePrediction(for: targetId)
        }
    }

    /// Get display name for a target ID
    func targetName(for targetId: String) -> String {
        // Check built-in targets
        if let target = PredictionTarget.allTargets.first(where: { $0.id == targetId }) {
            return target.name
        }
        // Check custom targets
        if let target = customTargets.first(where: { $0.id == targetId }) {
            return target.name
        }
        // For arbitrary health keys, clean up the name
        return targetId
            .replacingOccurrences(of: " (count)", with: "")
            .replacingOccurrences(of: " (count/min)", with: "")
            .replacingOccurrences(of: " (ms)", with: "")
            .replacingOccurrences(of: " (hr)", with: "")
            .replacingOccurrences(of: " (%)", with: "")
    }

    // MARK: - Custom Targets

    @Published var customTargets: [PredictionTarget] = []

    func loadCustomTargets() {
        if let data = UserDefaults.standard.data(forKey: "customPredictionTargets"),
           let targets = try? JSONDecoder().decode([CustomTarget].self, from: data) {
            customTargets = targets.map {
                PredictionTarget(id: $0.healthKey, name: $0.name, description: "Predict \($0.name.lowercased()) from facial analysis", icon: "plus.circle")
            }
        }
    }

    func addCustomTarget(name: String, healthKey: String) {
        let target = PredictionTarget(id: healthKey, name: name, description: "Predict \(name.lowercased()) from facial analysis", icon: "plus.circle")
        customTargets.append(target)
        saveCustomTargets()

        // Also add to available targets
        availableTargets.append(target)

        // Auto-select the new target and set initial status
        selectedTargets.insert(target.id)
        saveSelectedTargets()
        modelStatus[target.id] = .notTrained

        // Trigger training for the new target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.retrainAllModels()
        }
    }

    func removeCustomTarget(_ targetId: String) {
        customTargets.removeAll { $0.id == targetId }
        availableTargets.removeAll { $0.id == targetId }
        selectedTargets.remove(targetId)
        saveCustomTargets()
        saveSelectedTargets()
    }

    private func saveCustomTargets() {
        let customs = customTargets.map { CustomTarget(name: $0.name, healthKey: $0.id) }
        if let data = try? JSONEncoder().encode(customs) {
            UserDefaults.standard.set(data, forKey: "customPredictionTargets")
        }
    }
}

struct CustomTarget: Codable {
    let name: String
    let healthKey: String
}

/// Used to pass data to the model detail sheet via sheet(item:)
struct ModelDetailSelection: Identifiable {
    let id = UUID()
    let targetId: String
    let targetName: String
}

// MARK: - Data Models

struct PredictionTarget: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String

    static let allTargets: [PredictionTarget] = [
        PredictionTarget(
            id: "sleepScore",
            name: "Sleep Score",
            description: "Oura-inspired 0-100 score based on duration, deep sleep, REM, and efficiency",
            icon: "bed.double.fill"
        ),
        PredictionTarget(
            id: "hrv",
            name: "Heart Rate Variability",
            description: "Predict your HRV based on facial stress indicators",
            icon: "waveform.path.ecg"
        ),
        PredictionTarget(
            id: "restingHR",
            name: "Resting Heart Rate",
            description: "Predict resting heart rate from facial cues",
            icon: "heart.fill"
        )
    ]
}

enum ModelTrainingStatus {
    case notTrained
    case training
    case trained(correlation: Double)
    case failed(String)
}

// MARK: - Import Folder Picker View

struct ImportFolderPickerView: UIViewControllerRepresentable {
    let onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (URL?) -> Void

        init(onComplete: @escaping (URL?) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(nil)
        }
    }
}

// MARK: - Prediction Capture View

struct PredictionCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FaceToHealthViewModel
    @StateObject private var analysisCoordinator = FaceAnalysisCoordinator()
    @StateObject private var exporter = HealthDataExporter()

    @State private var capturedImage: UIImage?
    @State private var capturedMetrics: FacialMetrics?
    @State private var showingResults = false
    @State private var livePredictions: [String: Double] = [:]
    @State private var selectedTargetsCopy: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            if showingResults, let image = capturedImage {
                predictionResultsView(image: image)
            } else {
                FaceCaptureView(
                    onCapture: { image, metrics in
                        capturedImage = image
                        capturedMetrics = metrics
                        computePredictions(metrics: metrics)
                        // Save the capture so Latest Predictions updates
                        saveCapture(image: image, metrics: metrics)
                        showingResults = true
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            }
        }
        .onAppear {
            selectedTargetsCopy = viewModel.selectedTargets
        }
    }

    /// Save the captured image to the data store with health data
    private func saveCapture(image: UIImage, metrics: FacialMetrics?) {
        guard let metrics = metrics else { return }
        isSaving = true

        exporter.exportHealthDataRaw(for: Date()) { healthData in
            DispatchQueue.main.async {
                do {
                    try FacialDataStore.shared.saveCapture(
                        image: image,
                        metrics: metrics,
                        healthData: healthData ?? [:],
                        date: Date()
                    )
                    // Mark that user has made an explicit prediction
                    viewModel.hasMadePrediction = true
                    // Update predictions in view model
                    viewModel.updateAllPredictions()
                } catch {
                    print("Failed to save capture: \(error)")
                }
                isSaving = false
            }
        }
    }

    private func predictionResultsView(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Face image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 5)

                // Predictions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Predicted Health Metrics")
                        .font(.headline)

                    if livePredictions.isEmpty {
                        Text("No models trained yet. Capture more faces to train models.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sortedLivePredictions, id: \.0) { targetId, prediction in
                            LivePredictionRow(
                                targetId: targetId,
                                targetName: viewModel.targetName(for: targetId),
                                prediction: prediction,
                                confidence: getConfidence(for: targetId)
                            )
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Facial metrics summary
                if let metrics = capturedMetrics {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Facial Analysis")
                            .font(.headline)

                        HStack(spacing: 16) {
                            MetricBadge(label: "Alertness", value: Int(metrics.healthIndicators.alertnessScore))
                            MetricBadge(label: "Tension", value: Int(metrics.healthIndicators.tensionScore))
                            MetricBadge(label: "Mood", value: Int(metrics.healthIndicators.smileScore))
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        showingResults = false
                        capturedImage = nil
                        capturedMetrics = nil
                        livePredictions = [:]
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Another")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button(action: { dismiss() }) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Health Prediction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }

    private func computePredictions(metrics: FacialMetrics?) {
        guard let metrics = metrics else { return }

        let trainer = FaceHealthModelTrainer()
        for targetId in selectedTargetsCopy {
            if let prediction = trainer.predict(for: targetId, metrics: metrics) {
                livePredictions[targetId] = prediction
            }
        }
    }

    /// Get model confidence (R value) for a target
    private func getConfidence(for targetId: String) -> Double? {
        if let status = viewModel.modelStatus[targetId],
           case .trained(let correlation) = status {
            return correlation
        }
        return nil
    }

    /// Returns predictions sorted by confidence (highest first)
    private var sortedLivePredictions: [(String, Double)] {
        livePredictions.sorted { pair1, pair2 in
            let conf1 = getConfidence(for: pair1.key) ?? -1
            let conf2 = getConfidence(for: pair2.key) ?? -1
            return conf1 > conf2
        }.map { ($0.key, $0.value) }
    }
}

// MARK: - Live Prediction Row

private struct LivePredictionRow: View {
    let targetId: String
    let targetName: String
    let prediction: Double
    let confidence: Double?

    var body: some View {
        HStack {
            Image(systemName: iconForTarget(targetId))
                .foregroundColor(.purple)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(targetName)
                    .font(.subheadline)

                // Confidence indicator
                if let conf = confidence {
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", conf * 100))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(confidenceColor(conf))
                    }
                }
            }

            Spacer()

            Text(formatPrediction(prediction, for: targetId))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(colorForPrediction(prediction, targetId: targetId))
        }
        .padding(.vertical, 8)
    }

    private func iconForTarget(_ targetId: String) -> String {
        switch targetId {
        case "sleepScore": return "bed.double.fill"
        case "hrv": return "waveform.path.ecg"
        case "restingHR": return "heart.fill"
        default: return "chart.line.uptrend.xyaxis"
        }
    }

    private func confidenceColor(_ value: Double) -> Color {
        if value >= 0.5 {
            return .green
        } else if value >= 0.3 {
            return .orange
        } else {
            return .red
        }
    }

    private func formatPrediction(_ value: Double, for targetId: String) -> String {
        switch targetId {
        case "sleepScore":
            return String(format: "%.0f", max(0, min(100, value)))
        case "hrv":
            return String(format: "%.0f ms", max(0, value))
        case "restingHR":
            return String(format: "%.0f bpm", max(0, value))
        default:
            return String(format: "%.1f", value)
        }
    }

    private func colorForPrediction(_ value: Double, targetId: String) -> Color {
        switch targetId {
        case "sleepScore":
            return value >= 70 ? .green : (value >= 50 ? .orange : .red)
        case "hrv":
            return value >= 50 ? .green : (value >= 30 ? .orange : .red)
        case "restingHR":
            return value <= 60 ? .green : (value <= 80 ? .orange : .red)
        default:
            return .primary
        }
    }
}

// MARK: - Metric Badge

private struct MetricBadge: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(colorForValue(value))
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(colorForValue(value).opacity(0.1))
        .cornerRadius(8)
    }

    private func colorForValue(_ value: Int) -> Color {
        switch value {
        case 70...100: return .green
        case 40..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - Photos Picker Sheet

struct PhotosPickerSheet: View {
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isCheckingAuth = true
    @State private var localSelection: [PhotosPickerItem] = []  // Local state to avoid binding issues

    var body: some View {
        NavigationStack {
            Group {
                if isCheckingAuth {
                    ProgressView("Checking photo access...")
                } else if authorizationStatus == .authorized || authorizationStatus == .limited {
                    PhotosPicker(
                        selection: $localSelection,
                        maxSelectionCount: 100,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 20) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)

                            Text("Select Photos to Import")
                                .font(.headline)

                            Text("Choose photos containing faces to analyze and import into your Face-to-Health data.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Text("Tap here to open photo library")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.top, 10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                    // Permission denied - show settings prompt
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("Photo Access Required")
                            .font(.headline)

                        Text("ShareHealth needs access to your photo library to import face photos. Please enable access in Settings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Not determined - will request
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Requesting photo access...")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Import Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: localSelection) { _, newItems in
                if !newItems.isEmpty {
                    // Transfer to parent binding and dismiss
                    selectedPhotos = newItems
                    dismiss()
                }
            }
            .onAppear {
                // Clear local selection on appear
                localSelection = []
                checkAndRequestAuthorization()
            }
        }
    }

    private func checkAndRequestAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.authorizationStatus = newStatus
                    self.isCheckingAuth = false
                }
            }
        } else {
            authorizationStatus = status
            isCheckingAuth = false
        }
    }
}

// MARK: - Expanded Image View

struct ExpandedImageView: View {
    let image: UIImage?
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                // Limit scale bounds
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                } else if scale > 5.0 {
                                    withAnimation {
                                        scale = 5.0
                                        lastScale = 5.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }

            // Instructions
            VStack {
                Spacer()
                Text("Pinch to zoom • Double-tap to toggle zoom • Tap X to close")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            }
        }
    }
}

// MARK: - Model Snapshot Manager View

struct ModelSnapshotManagerView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FaceToHealthViewModel
    let onResult: (String) -> Void

    @State private var snapshots: [ModelSnapshot] = []
    @State private var isLoading = true
    @State private var showingDeleteConfirm = false
    @State private var snapshotToDelete: ModelSnapshot?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading snapshots...")
                } else if snapshots.isEmpty {
                    emptyStateView
                } else {
                    snapshotListView
                }
            }
            .navigationTitle("Restore Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSnapshots()
            }
            .alert("Delete Snapshot?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let snapshot = snapshotToDelete {
                        deleteSnapshot(snapshot)
                    }
                }
            } message: {
                if let snapshot = snapshotToDelete {
                    Text("Delete '\(snapshot.name)'? This cannot be undone.")
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Saved Snapshots")
                .font(.headline)

            Text("Save your current models to create a snapshot you can restore later.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var snapshotListView: some View {
        List {
            ForEach(snapshots) { snapshot in
                SnapshotRowView(snapshot: snapshot)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        restoreSnapshot(snapshot)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            snapshotToDelete = snapshot
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private func loadSnapshots() {
        let trainer = FaceHealthModelTrainer()
        snapshots = trainer.listSnapshots()
        isLoading = false
    }

    private func restoreSnapshot(_ snapshot: ModelSnapshot) {
        let trainer = FaceHealthModelTrainer()
        do {
            try trainer.restoreSnapshot(id: snapshot.id)

            // Update model status for restored targets
            for targetId in snapshot.targetIds {
                if let correlation = trainer.getModelCorrelation(for: targetId) {
                    viewModel.modelStatus[targetId] = .trained(correlation: correlation)
                }
            }

            // Update predictions
            viewModel.updateAllPredictions()

            dismiss()
            onResult("Restored '\(snapshot.name)' with \(snapshot.targetCount) models")
        } catch {
            onResult("Restore failed: \(error.localizedDescription)")
        }
    }

    private func deleteSnapshot(_ snapshot: ModelSnapshot) {
        let trainer = FaceHealthModelTrainer()
        trainer.deleteSnapshot(id: snapshot.id)
        snapshots.removeAll { $0.id == snapshot.id }
    }
}

private struct SnapshotRowView: View {
    let snapshot: ModelSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)

                Text(snapshot.name)
                    .font(.headline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("\(snapshot.targetCount) models")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Text(formatDate(snapshot.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    FaceToHealthView()
}
