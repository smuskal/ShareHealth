import SwiftUI
import UniformTypeIdentifiers
import HealthKit
import AVFoundation

struct HealthExportView: View {
    @StateObject private var exporter = HealthDataExporter()
    @State private var selectedDate = Date()
    @State private var isAuthorized = UserDefaults.standard.bool(forKey: "healthExportAuthorized")
    @State private var isRequestingAuth = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var showingFolderPicker = false
    @State private var defaultFolderURL: URL? = nil
    @State private var defaultFolderName: String = ""

    // Face imagery feature
    @State private var includeFaceImagery = UserDefaults.standard.bool(forKey: "includeFaceImagery")
    @State private var showingFaceCapture = false
    @State private var pendingExportURL: URL? = nil
    @State private var showingCameraPermissionAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                Divider()
                    .padding(.horizontal)

                if !isAuthorized {
                    authorizationSection
                } else {
                    authorizedContentSection
                }

                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Health Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkAuthorization()
            loadDefaultFolder()
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView { url in
                if let url = url {
                    saveDefaultFolder(url)
                }
                showingFolderPicker = false
            }
        }
        .alert("Export Successful", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your health data has been exported successfully.")
        }
        .alert("Export Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showingFaceCapture) {
            FaceCaptureView(
                onCapture: { image in
                    handleFaceCaptured(image)
                },
                onCancel: {
                    // User cancelled - cancel the entire export
                    cancelPendingExport()
                }
            )
        }
        .alert("Camera Access Required", isPresented: $showingCameraPermissionAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {
                // User cancelled - cancel the entire export
                cancelPendingExport()
            }
        } message: {
            Text("To include face imagery with your exports, please enable camera access in Settings.")
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Export Health Data")
                .font(.title)
                .fontWeight(.bold)

            Text("Export all your Apple Health metrics to a CSV file")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - Authorization Section
    private var authorizationSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Health Data Access Required")
                .font(.headline)

            Text("To export your health data, this app needs permission to read your Apple Health information.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: requestAuthorization) {
                if isRequestingAuth {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Grant Health Access")
                }
            }
            .frame(minWidth: 200)
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isRequestingAuth)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Authorized Content Section
    private var authorizedContentSection: some View {
        VStack(spacing: 20) {
            exportButtonsSection

            if exporter.isExporting {
                exportProgressSection
            }

            dateSelectionSection
            exportLocationSection
            fileNamingSection
            faceImagerySection
        }
    }

    // MARK: - Date Selection
    private var dateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Date")
                .font(.headline)

            DatePicker(
                "Export Date",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
    }

    // MARK: - Export Location
    private var exportLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Location")
                .font(.headline)

            if defaultFolderURL != nil {
                folderSelectedView
            } else {
                setFolderButton
            }
        }
        .padding(.horizontal)
    }

    private var folderSelectedView: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
            Text(defaultFolderName)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("Change") {
                showingFolderPicker = true
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var setFolderButton: some View {
        Button(action: { showingFolderPicker = true }) {
            HStack {
                Image(systemName: "folder.badge.plus")
                Text("Set Default Folder")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    // MARK: - Export Progress
    private var exportProgressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: exporter.exportProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))

            Text("Exporting: \(exporter.currentMetric)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(Int(exporter.exportProgress * 100))%")
                .font(.headline)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Export Buttons
    private var exportButtonsSection: some View {
        VStack(spacing: 12) {
            if defaultFolderURL != nil {
                quickExportButton
            }
            shareSheetButton
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var quickExportButton: some View {
        Button(action: quickExport) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Export to Default Folder")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(exporter.isExporting)
    }

    @ViewBuilder
    private var shareSheetButton: some View {
        if defaultFolderURL != nil {
            Button(action: exportWithShareSheet) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export to Other Location...")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .controlSize(.large)
            .disabled(exporter.isExporting)
        } else {
            Button(action: exportWithShareSheet) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export to CSV")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(exporter.isExporting)
        }
    }

    // MARK: - File Naming Info
    private var fileNamingSection: some View {
        VStack(spacing: 4) {
            Text("File will be saved to:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(formatYearMonth(selectedDate))/HealthMetrics-\(formatDateForFilename(selectedDate)).csv")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
        }
        .padding(.top, 8)
    }

    // MARK: - Face Imagery Section
    private var faceImagerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.top, 8)

            Toggle(isOn: $includeFaceImagery) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Face Imagery")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Take a selfie with each export")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .onChange(of: includeFaceImagery) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "includeFaceImagery")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Functions

    private func checkAuthorization() {
        isAuthorized = UserDefaults.standard.bool(forKey: "healthExportAuthorized")
    }

    private func requestAuthorization() {
        isRequestingAuth = true
        exporter.requestFullAuthorization { _ in
            DispatchQueue.main.async {
                isRequestingAuth = false
                UserDefaults.standard.set(true, forKey: "healthExportAuthorized")
                isAuthorized = true
            }
        }
    }

    private func loadDefaultFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "defaultExportFolderBookmark") else {
            return
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)

            if isStale {
                UserDefaults.standard.removeObject(forKey: "defaultExportFolderBookmark")
                UserDefaults.standard.removeObject(forKey: "defaultExportFolderName")
                return
            }

            defaultFolderURL = url
            defaultFolderName = UserDefaults.standard.string(forKey: "defaultExportFolderName") ?? url.lastPathComponent
        } catch {
            print("Failed to resolve bookmark: \(error)")
            UserDefaults.standard.removeObject(forKey: "defaultExportFolderBookmark")
        }
    }

    private func saveDefaultFolder(_ url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access security-scoped resource")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "defaultExportFolderBookmark")
            UserDefaults.standard.set(url.lastPathComponent, forKey: "defaultExportFolderName")

            defaultFolderURL = url
            defaultFolderName = url.lastPathComponent
        } catch {
            print("Failed to create bookmark: \(error)")
            errorMessage = "Failed to save folder location: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func quickExport() {
        guard let folderURL = defaultFolderURL else { return }

        exporter.exportHealthData(for: selectedDate) { tempURL, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error
                    self.showingError = true
                    return
                }

                guard let tempURL = tempURL else {
                    self.errorMessage = "Failed to generate CSV"
                    self.showingError = true
                    return
                }

                // Store the pending export URL
                self.pendingExportURL = tempURL

                // If face imagery is enabled, show camera first
                if self.includeFaceImagery {
                    self.checkCameraPermissionAndShowCapture()
                } else {
                    self.copyToDefaultFolder(from: tempURL, to: folderURL)
                }
            }
        }
    }

    private func checkCameraPermissionAndShowCapture() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingFaceCapture = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showingFaceCapture = true
                    } else {
                        self.showingCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingCameraPermissionAlert = true
        @unknown default:
            completePendingExport()
        }
    }

    private func handleFaceCaptured(_ image: UIImage) {
        guard let folderURL = defaultFolderURL else {
            completePendingExport()
            return
        }

        // Save the face image to the faces/YYYY/MM subfolder
        guard folderURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access the export folder. Please set the folder again."
            showingError = true
            UserDefaults.standard.removeObject(forKey: "defaultExportFolderBookmark")
            defaultFolderURL = nil
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        // Create faces/YYYY/MM subfolder structure
        let yearMonthPath = formatYearMonth(selectedDate)
        let facesFolder = folderURL
            .appendingPathComponent("faces", isDirectory: true)
            .appendingPathComponent(yearMonthPath, isDirectory: true)
        do {
            if !FileManager.default.fileExists(atPath: facesFolder.path) {
                try FileManager.default.createDirectory(at: facesFolder, withIntermediateDirectories: true)
            }

            // Save the image with timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let imageName = "Face-\(timestamp).jpg"
            let imageURL = facesFolder.appendingPathComponent(imageName)

            if let imageData = image.jpegData(compressionQuality: 0.85) {
                try imageData.write(to: imageURL)
                print("Face image saved to: \(imageURL.path)")
            }
        } catch {
            print("Failed to save face image: \(error.localizedDescription)")
            // Continue with export even if face save fails
        }

        // Now complete the CSV export
        completePendingExport()
    }

    private func completePendingExport() {
        guard let tempURL = pendingExportURL, let folderURL = defaultFolderURL else {
            pendingExportURL = nil
            return
        }

        copyToDefaultFolder(from: tempURL, to: folderURL)
        pendingExportURL = nil
    }

    private func cancelPendingExport() {
        // Clean up the temp file if it exists
        if let tempURL = pendingExportURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        pendingExportURL = nil
        // No success message - export was cancelled
    }

    private func copyToDefaultFolder(from sourceURL: URL, to folderURL: URL) {
        guard folderURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access the export folder. Please set the folder again."
            showingError = true
            UserDefaults.standard.removeObject(forKey: "defaultExportFolderBookmark")
            defaultFolderURL = nil
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        do {
            // Create year/month subfolder structure
            let yearMonthPath = formatYearMonth(selectedDate)
            let subfolderURL = folderURL.appendingPathComponent(yearMonthPath, isDirectory: true)

            if !FileManager.default.fileExists(atPath: subfolderURL.path) {
                try FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
            }

            let fileName = sourceURL.lastPathComponent
            let destinationURL = subfolderURL.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            showingSuccess = true
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func formatYearMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        return formatter.string(from: date)
    }

    private func exportWithShareSheet() {
        exporter.exportHealthData(for: selectedDate) { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error
                    self.showingError = true
                } else if let url = url {
                    self.presentShareSheet(with: url)
                }
            }
        }
    }

    private func presentShareSheet(with url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Could not present share sheet"
            showingError = true
            return
        }

        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                DispatchQueue.main.async {
                    self.showingSuccess = true
                }
            }
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topController.present(activityVC, animated: true)
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct ExportInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct FolderPickerView: UIViewControllerRepresentable {
    let onPicked: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL?) -> Void

        init(onPicked: @escaping (URL?) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPicked(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPicked(nil)
        }
    }
}

#Preview {
    NavigationStack {
        HealthExportView()
    }
}
