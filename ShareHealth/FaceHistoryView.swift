import SwiftUI
import PhotosUI

/// Browse historical face captures with their metrics
struct FaceHistoryView: View {
    @ObservedObject private var dataStore = FacialDataStore.shared
    @StateObject private var importer = FaceDataImporter()
    @State private var selectedCapture: StoredFaceCapture? = nil
    @State private var showingPurgeConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var captureToDelete: StoredFaceCapture? = nil
    @State private var showingFaceCapture = false

    // Multi-select state
    @State private var isEditMode = false
    @State private var selectedCaptureIds: Set<String> = []
    @State private var showingMultiDeleteConfirmation = false

    // Import state
    @State private var showingImportPicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingImportResult = false
    @State private var importResultMessage = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if dataStore.isLoading {
                    loadingView
                } else if dataStore.captures.isEmpty {
                    emptyStateView
                } else {
                    captureGridView
                }
            }
            .navigationTitle("Face History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditMode {
                        Button("Cancel") {
                            isEditMode = false
                            selectedCaptureIds.removeAll()
                        }
                    } else {
                        Button(action: { showingFaceCapture = true }) {
                            Image(systemName: "camera.fill")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button(selectedCaptureIds.isEmpty ? "Select All" : "Delete (\(selectedCaptureIds.count))") {
                            if selectedCaptureIds.isEmpty {
                                // Select all
                                selectedCaptureIds = Set(dataStore.captures.map { $0.id })
                            } else {
                                // Delete selected
                                showingMultiDeleteConfirmation = true
                            }
                        }
                        .foregroundColor(selectedCaptureIds.isEmpty ? .blue : .red)
                    } else {
                        Menu {
                            // Import options
                            Button(action: { showingImportPicker = true }) {
                                Label("Import from Export Folder", systemImage: "folder")
                            }

                            Button(action: { showingPhotoPicker = true }) {
                                Label("Import from Photos", systemImage: "photo.on.rectangle")
                            }

                            Divider()

                            if !dataStore.captures.isEmpty {
                                Button(action: { isEditMode = true }) {
                                    Label("Select Multiple", systemImage: "checkmark.circle")
                                }
                            }

                            Button(action: { dataStore.loadCaptures() }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }

                            if !dataStore.captures.isEmpty {
                                Divider()
                                Button(role: .destructive, action: { showingPurgeConfirmation = true }) {
                                    Label("Delete All Data", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingFaceCapture) {
                StandaloneFaceCaptureView(
                    onCapture: { _, _ in },
                    onCancel: { }
                )
            }
            .onAppear {
                dataStore.loadCaptures()
            }
            .sheet(item: $selectedCapture) { capture in
                CaptureDetailView(capture: capture, onDelete: {
                    captureToDelete = capture
                    selectedCapture = nil
                    showingDeleteConfirmation = true
                })
            }
            .alert("Delete All Face Data?", isPresented: $showingPurgeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    purgeAllData()
                }
            } message: {
                Text("This will permanently delete all \(dataStore.captureCount) stored face images and their metrics. This cannot be undone.")
            }
            .alert("Delete This Capture?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    captureToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let capture = captureToDelete {
                        deleteCapture(capture)
                    }
                    captureToDelete = nil
                }
            } message: {
                Text("This will permanently delete this face image and its metrics.")
            }
            .alert("Delete \(selectedCaptureIds.count) Captures?", isPresented: $showingMultiDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(selectedCaptureIds.count)", role: .destructive) {
                    deleteSelectedCaptures()
                }
            } message: {
                Text("This will permanently delete the selected face images and their metrics.")
            }
            .sheet(isPresented: $showingImportPicker) {
                FolderPickerView { url in
                    if let url = url {
                        importer.importFromFolder(url: url) { result in
                            importResultMessage = result.message
                            showingImportResult = true
                        }
                    }
                    showingImportPicker = false
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotosPickerSheet(selectedPhotos: $selectedPhotos)
            }
            .onChange(of: selectedPhotos) { _, newPhotos in
                if !newPhotos.isEmpty {
                    importPhotosFromLibrary(items: newPhotos)
                    selectedPhotos = []
                }
            }
            .alert("Import Result", isPresented: $showingImportResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importResultMessage)
            }
            .overlay {
                if importer.isImporting {
                    importProgressOverlay
                }
            }
        }
    }

    // MARK: - Import from Photos

    private func importPhotosFromLibrary(items: [PhotosPickerItem]) {
        let analyzer = MediaPipeFaceAnalyzer()
        let total = items.count
        var imported = 0
        var failed = 0

        Task {
            for item in items {
                // Load the image data - import exactly as saved (no transformation)
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    failed += 1
                    continue
                }

                // Get the photo's creation date if available
                let photoDate = await getPhotoDate(for: item) ?? Date()

                // Analyze with MediaPipe
                let metrics = await withCheckedContinuation { continuation in
                    analyzer.analyze(image: image) { result in
                        continuation.resume(returning: result)
                    }
                }

                guard let metrics = metrics else {
                    failed += 1
                    continue
                }

                // Save to FacialDataStore (no health data - will need backfill)
                do {
                    try FacialDataStore.shared.saveCapture(
                        image: image,
                        metrics: metrics,
                        healthData: [:],
                        date: photoDate
                    )
                    imported += 1
                } catch {
                    failed += 1
                }
            }

            await MainActor.run {
                importResultMessage = "Imported \(imported) photos" +
                    (failed > 0 ? ", \(failed) failed" : "")
                showingImportResult = true
                dataStore.loadCaptures()
            }
        }
    }

    private func getPhotoDate(for item: PhotosPickerItem) async -> Date? {
        guard let identifier = item.itemIdentifier else { return nil }
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return results.firstObject?.creationDate
    }

    // MARK: - Import Progress Overlay

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: importer.importProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(width: 200)

                Text(importer.currentFile)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(importer.importedCount) imported, \(importer.skippedCount) skipped")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(24)
            .background(Color(.systemGray5))
            .cornerRadius(16)
        }
    }

    private func deleteSelectedCaptures() {
        for id in selectedCaptureIds {
            if let capture = dataStore.captures.first(where: { $0.id == id }) {
                try? dataStore.deleteCapture(capture)
            }
        }
        selectedCaptureIds.removeAll()
        isEditMode = false
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading captures...")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Face Captures")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Face images will appear here when you export health data with face imagery enabled.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Grouped captures by day

    private var capturesByDay: [(date: Date, captures: [StoredFaceCapture])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: dataStore.captures) { capture in
            calendar.startOfDay(for: capture.captureDate)
        }
        return grouped.map { (date: $0.key, captures: $0.value.sorted { $0.captureDate < $1.captureDate }) }
            .sorted { $0.date > $1.date }  // Most recent day first
    }

    // MARK: - Capture Grid

    private var captureGridView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Statistics header
                statisticsHeader

                // Grouped by day
                ForEach(capturesByDay, id: \.date) { dayGroup in
                    VStack(alignment: .leading, spacing: 8) {
                        // Day header
                        HStack {
                            Text(formatDayHeader(dayGroup.date))
                                .font(.headline)
                            Spacer()
                            Text("\(dayGroup.captures.count) capture\(dayGroup.captures.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        // Grid of captures for this day
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(dayGroup.captures) { capture in
                                CaptureGridItem(
                                    capture: capture,
                                    isEditMode: isEditMode,
                                    isSelected: selectedCaptureIds.contains(capture.id)
                                )
                                .onTapGesture {
                                    if isEditMode {
                                        // Toggle selection
                                        if selectedCaptureIds.contains(capture.id) {
                                            selectedCaptureIds.remove(capture.id)
                                        } else {
                                            selectedCaptureIds.insert(capture.id)
                                        }
                                    } else {
                                        selectedCapture = capture
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func formatDayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }

    private var statisticsHeader: some View {
        HStack(spacing: 20) {
            StatBox(title: "Captures", value: "\(dataStore.captureCount)")
            StatBox(title: "Storage", value: dataStore.formattedStorageSize)

            if let oldest = dataStore.oldestCapture {
                StatBox(title: "Since", value: formatShortDate(oldest))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func purgeAllData() {
        do {
            try dataStore.purgeAllCaptures()
        } catch {
            print("Failed to purge: \(error)")
        }
    }

    private func deleteCapture(_ capture: StoredFaceCapture) {
        do {
            try dataStore.deleteCapture(capture)
        } catch {
            print("Failed to delete: \(error)")
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Capture Grid Item

private struct CaptureGridItem: View {
    let capture: StoredFaceCapture
    let isEditMode: Bool
    let isSelected: Bool
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 100, height: 100)
                        .overlay(
                            ProgressView()
                        )
                }

                // Selection checkbox in edit mode
                if isEditMode {
                    VStack {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .white)
                                .font(.title3)
                                .background(
                                    Circle()
                                        .fill(isSelected ? .white : .black.opacity(0.3))
                                        .padding(-2)
                                )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                } else if capture.hasMetrics {
                    // Metrics indicator (only in non-edit mode)
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                                .background(Circle().fill(.white).padding(-2))
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }

            Text(formatDate(capture.captureDate))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = capture.loadImage() {
                // Create thumbnail
                let size = CGSize(width: 200, height: 200)
                UIGraphicsBeginImageContextWithOptions(size, false, 0)
                image.draw(in: CGRect(origin: .zero, size: size))
                let thumb = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                DispatchQueue.main.async {
                    self.thumbnail = thumb
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"  // 12-hour format with AM/PM
        return formatter.string(from: date)
    }
}

// MARK: - Capture Detail View

struct CaptureDetailView: View {
    let capture: StoredFaceCapture
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: UIImage? = nil
    @State private var showingMetrics = false
    @State private var showingExpandedImage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    imageSection

                    // Date/Time
                    dateSection

                    // Quick metrics summary
                    if let metrics = capture.metrics {
                        metricsSection(metrics)
                    }

                    // Health data summary
                    if let health = capture.healthData, !health.isEmpty {
                        healthSection(health)
                    }

                    // Actions
                    actionSection
                }
                .padding()
            }
            .navigationTitle("Capture Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMetrics) {
                if let metrics = capture.metrics {
                    FacialMetricsDetailView(metrics: metrics)
                }
            }
            .fullScreenCover(isPresented: $showingExpandedImage) {
                ExpandedFaceImageView(image: fullImage) {
                    showingExpandedImage = false
                }
            }
        }
        .onAppear {
            loadFullImage()
        }
    }

    private var imageSection: some View {
        Group {
            if let image = fullImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .overlay(
                        // Expand button overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(12)
                    )
                    .onTapGesture {
                        showingExpandedImage = true
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: 300)
                    .overlay(ProgressView())
            }
        }
    }

    private var dateSection: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.secondary)
            Text(formatFullDate(capture.captureDate))
                .font(.subheadline)
            Spacer()
            Image(systemName: "clock")
                .foregroundColor(.secondary)
            Text(formatTime(capture.captureDate))
                .font(.subheadline)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func metricsSection(_ metrics: FacialMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Facial Metrics")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    showingMetrics = true
                }
                .font(.subheadline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetricPill(label: "Alertness", value: Int(metrics.healthIndicators.alertnessScore), color: colorForScore(metrics.healthIndicators.alertnessScore))
                MetricPill(label: "Tension", value: Int(metrics.healthIndicators.tensionScore), color: colorForTension(metrics.healthIndicators.tensionScore))
                MetricPill(label: "Mood", value: Int(metrics.healthIndicators.smileScore), color: colorForScore(metrics.healthIndicators.smileScore))
                MetricPill(label: "Symmetry", value: Int(metrics.healthIndicators.facialSymmetry), color: colorForScore(metrics.healthIndicators.facialSymmetry))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func healthSection(_ health: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Snapshot")
                .font(.headline)

            let keyMetrics = ["Step Count (count)", "Heart Rate [Avg] (count/min)", "Sleep Analysis [Total] (hr)", "Heart Rate Variability (ms)"]
            let availableMetrics = keyMetrics.compactMap { key -> (String, String)? in
                guard let value = health[key], !value.isEmpty else { return nil }
                return (key, value)
            }

            if availableMetrics.isEmpty {
                Text("No health data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(availableMetrics, id: \.0) { metric in
                    HStack {
                        Text(simplifyMetricName(metric.0))
                            .font(.subheadline)
                        Spacer()
                        Text(formatMetricValue(metric.1, for: metric.0))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var actionSection: some View {
        Button(role: .destructive, action: onDelete) {
            HStack {
                Image(systemName: "trash")
                Text("Delete Capture")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private func loadFullImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = capture.loadImage()
            DispatchQueue.main.async {
                self.fullImage = image
            }
        }
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 70...100: return .green
        case 40..<70: return .orange
        default: return .red
        }
    }

    private func colorForTension(_ score: Double) -> Color {
        switch score {
        case 0..<30: return .green
        case 30..<60: return .orange
        default: return .red
        }
    }

    private func simplifyMetricName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " (count)", with: "")
            .replacingOccurrences(of: " (count/min)", with: "")
            .replacingOccurrences(of: " (hr)", with: "")
            .replacingOccurrences(of: " (ms)", with: "")
            .replacingOccurrences(of: "[Avg]", with: "")
            .replacingOccurrences(of: "[Total]", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func formatMetricValue(_ value: String, for metric: String) -> String {
        guard let doubleValue = Double(value) else { return value }

        if metric.contains("(hr)") {
            return String(format: "%.1f hrs", doubleValue)
        } else if metric.contains("(ms)") {
            return String(format: "%.0f ms", doubleValue)
        } else if metric.contains("(count/min)") {
            return String(format: "%.0f bpm", doubleValue)
        } else {
            return String(format: "%.0f", doubleValue)
        }
    }
}

// MARK: - Metric Pill

private struct MetricPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Expanded Face Image View

struct ExpandedFaceImageView: View {
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
                Text("Pinch to zoom • Double-tap to toggle • Tap X to close")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            }
        }
    }
}

#Preview {
    FaceHistoryView()
}
