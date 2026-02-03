import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HistoricalExportView: View {
    @StateObject private var exporter = HealthDataExporter()
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var earliestAvailableDate: Date? = nil
    @State private var isAuthorized = UserDefaults.standard.bool(forKey: "healthExportAuthorized")
    @State private var isRequestingAuth = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var showingFolderPicker = false
    @State private var exportFolderURL: URL? = nil
    @State private var exportFolderName: String = ""

    // Export progress
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var currentExportStatus: String = ""
    @State private var totalDaysToExport: Int = 0
    @State private var currentDayIndex: Int = 0
    @State private var filesExported: Int = 0
    @State private var failedDays: [String] = []
    @State private var exportLog: [String] = []
    @State private var showingLog = false

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
        .navigationTitle("Historical Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkAuthorization()
            loadExportFolder()
            findEarliestDate()
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView { url in
                if let url = url {
                    saveExportFolder(url)
                }
                showingFolderPicker = false
            }
        }
        .alert("Export Complete", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
            if !exportLog.isEmpty {
                Button("View Log") {
                    showingLog = true
                }
            }
        } message: {
            if failedDays.isEmpty {
                Text("\(filesExported) daily CSV files exported successfully.")
            } else {
                Text("\(filesExported) files exported. \(failedDays.count) days failed.")
            }
        }
        .sheet(isPresented: $showingLog) {
            ExportLogView(log: exportLog, failedDays: failedDays)
        }
        .alert("Export Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Historical Export")
                .font(.title)
                .fontWeight(.bold)

            Text("Export daily health data for a date range")
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
            .tint(.orange)
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
            earliestDateInfoSection
            dateRangeSection
            folderSelectionSection

            if isExporting {
                exportProgressSection
            }

            exportButtonSection
            exportSummarySection
        }
    }

    // MARK: - Earliest Date Info
    private var earliestDateInfoSection: some View {
        Group {
            if let earliest = earliestAvailableDate {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Health data available from \(formatDisplayDate(earliest))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Use") {
                        startDate = earliest
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Date Range Selection
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker(
                        "",
                        selection: $startDate,
                        in: (earliestAvailableDate ?? Date.distantPast)...endDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker(
                        "",
                        selection: $endDate,
                        in: startDate...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    // MARK: - Folder Selection
    private var folderSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Folder")
                .font(.headline)

            if exportFolderURL != nil {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.orange)
                    Text(exportFolderName)
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
            } else {
                Button(action: { showingFolderPicker = true }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Select Export Folder")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Export Progress
    private var exportProgressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: exportProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .orange))

            Text(currentExportStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack {
                Text("\(Int(exportProgress * 100))%")
                    .font(.headline)

                Spacer()

                if totalDaysToExport > 0 {
                    Text("Day \(currentDayIndex) of \(totalDaysToExport)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Export Button
    private var exportButtonSection: some View {
        Button(action: startExport) {
            HStack {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "square.and.arrow.down.on.square")
                    Text("Export \(calculateDayCount()) Days")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.large)
        .disabled(isExporting || exportFolderURL == nil)
        .padding(.horizontal)
    }

    // MARK: - Export Summary
    private var exportSummarySection: some View {
        VStack(spacing: 8) {
            let days = calculateDayCount()

            Text("This will create \(days) individual CSV files")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Organized in year/month folders:")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("YYYY/MM/HealthMetrics-YYYY-MM-DD.csv")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Helper Functions

    private func calculateDayCount() -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: start, to: end)
        return (components.day ?? 0) + 1
    }

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
                findEarliestDate()
            }
        }
    }

    private func findEarliestDate() {
        exporter.findEarliestHealthDataDate { date in
            earliestAvailableDate = date
            if let date = date, startDate < date {
                startDate = date
            }
        }
    }

    private func loadExportFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "historicalExportFolderBookmark") else {
            return
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)

            if isStale {
                UserDefaults.standard.removeObject(forKey: "historicalExportFolderBookmark")
                UserDefaults.standard.removeObject(forKey: "historicalExportFolderName")
                return
            }

            exportFolderURL = url
            exportFolderName = UserDefaults.standard.string(forKey: "historicalExportFolderName") ?? url.lastPathComponent
        } catch {
            print("Failed to resolve bookmark: \(error)")
            UserDefaults.standard.removeObject(forKey: "historicalExportFolderBookmark")
        }
    }

    private func saveExportFolder(_ url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access security-scoped resource")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "historicalExportFolderBookmark")
            UserDefaults.standard.set(url.lastPathComponent, forKey: "historicalExportFolderName")

            exportFolderURL = url
            exportFolderName = url.lastPathComponent
        } catch {
            print("Failed to create bookmark: \(error)")
            errorMessage = "Failed to save folder location: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func startExport() {
        guard let folderURL = exportFolderURL else { return }

        // Keep screen awake during export
        UIApplication.shared.isIdleTimerDisabled = true

        isExporting = true
        exportProgress = 0.0
        currentExportStatus = "Preparing export..."
        filesExported = 0
        failedDays = []
        exportLog = []

        let days = calculateDayCount()
        totalDaysToExport = days
        currentDayIndex = 0

        logMessage("Starting export of \(days) days")
        logMessage("Folder URL: \(folderURL.absoluteString)")
        logMessage("Folder path: \(folderURL.path)")

        Task {
            await performHistoricalExport(to: folderURL)
            // Re-enable idle timer when done
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private func logMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        print("📊 EXPORT: \(logEntry)")
        exportLog.append(logEntry)
    }

    private func printExportLog() {
        print("📊 ===== EXPORT LOG =====")
        for entry in exportLog {
            print(entry)
        }
        print("📊 ===== END LOG =====")
    }

    private func performHistoricalExport(to folderURL: URL) async {
        guard folderURL.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                logMessage("ERROR: Cannot access export folder")
                errorMessage = "Cannot access the export folder. Please select the folder again."
                showingError = true
                isExporting = false
            }
            return
        }
        defer {
            folderURL.stopAccessingSecurityScopedResource()
            logMessage("Released folder access")
        }

        logMessage("Folder access granted")

        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let endDateNormalized = calendar.startOfDay(for: endDate)

        var dayIndex = 0
        var exportedCount = 0
        var failedCount = 0
        var localFailedDays: [String] = []

        while currentDate <= endDateNormalized {
            dayIndex += 1
            let dateString = formatDateForFilename(currentDate)

            await MainActor.run {
                currentDayIndex = dayIndex
                currentExportStatus = "Exporting \(dateString)..."
                exportProgress = Double(dayIndex) / Double(totalDaysToExport)
            }

            // Export this day's data with timeout protection
            do {
                let dayData = try await withTimeout(seconds: 30) {
                    await self.exportSingleDay(date: currentDate)
                }

                if let dayData = dayData {
                    // Create year/month subfolder structure
                    let yearMonth = formatYearMonth(currentDate)
                    let subfolderURL = folderURL.appendingPathComponent(yearMonth, isDirectory: true)

                    if !FileManager.default.fileExists(atPath: subfolderURL.path) {
                        try FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
                    }

                    let fileName = "HealthMetrics-\(dateString).csv"
                    let fileURL = subfolderURL.appendingPathComponent(fileName)

                    let csvContent = generateCSVContent(data: dayData, date: currentDate)

                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                    try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    exportedCount += 1

                    // Log every 10 days or on specific milestones
                    if dayIndex % 10 == 0 || dayIndex == 1 {
                        await MainActor.run {
                            logMessage("Progress: \(dayIndex)/\(totalDaysToExport) - Saved \(dateString)")
                            logMessage("File: \(fileURL.path)")
                        }
                    }
                } else {
                    failedCount += 1
                    localFailedDays.append(dateString)
                    await MainActor.run {
                        logMessage("WARNING: No data returned for \(dateString)")
                    }
                }
            } catch {
                failedCount += 1
                localFailedDays.append(dateString)
                await MainActor.run {
                    logMessage("ERROR: Failed \(dateString) - \(error.localizedDescription)")
                }
                // Continue to next day instead of stopping
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        await MainActor.run {
            filesExported = exportedCount
            failedDays = localFailedDays
            exportProgress = 1.0
            currentExportStatus = "Export complete!"
            isExporting = false
            logMessage("Export finished: \(exportedCount) succeeded, \(failedCount) failed")
            showingSuccess = true
        }
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async -> T?) async throws -> T? {
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                return await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ExportError.timeout
            }

            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    enum ExportError: Error, LocalizedError {
        case timeout

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "Operation timed out"
            }
        }
    }

    private func exportSingleDay(date: Date) async -> [String: String]? {
        return await withCheckedContinuation { continuation in
            exporter.exportHealthDataRaw(for: date) { data in
                continuation.resume(returning: data)
            }
        }
    }

    private func generateCSVContent(data: [String: String], date: Date) -> String {
        let csvColumnOrder: [String] = [
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
            "Bedtime",
            "Wake Time",
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

        let header = csvColumnOrder.joined(separator: ",")

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = timestampFormatter.string(from: Calendar.current.startOfDay(for: date))

        var rowValues: [String] = []
        for column in csvColumnOrder {
            if column == "Date/Time" {
                rowValues.append(timestamp)
            } else {
                rowValues.append(data[column] ?? "")
            }
        }
        let dataRow = rowValues.joined(separator: ",")

        return header + "\n" + dataRow + "\n"
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatYearMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        return formatter.string(from: date)
    }

    private func formatDisplayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Export Log View
struct ExportLogView: View {
    let log: [String]
    let failedDays: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !failedDays.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Failed Days (\(failedDays.count))")
                                .font(.headline)
                                .foregroundColor(.red)

                            ForEach(failedDays, id: \.self) { day in
                                Text(day)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export Log")
                            .font(.headline)

                        ForEach(log, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Export Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    ShareLink(item: logAsText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var logAsText: String {
        var text = "ShareHealth Export Log\n"
        text += "=======================\n\n"

        if !failedDays.isEmpty {
            text += "Failed Days (\(failedDays.count)):\n"
            for day in failedDays {
                text += "  - \(day)\n"
            }
            text += "\n"
        }

        text += "Log:\n"
        for entry in log {
            text += "\(entry)\n"
        }

        return text
    }
}

#Preview {
    NavigationStack {
        HistoricalExportView()
    }
}
