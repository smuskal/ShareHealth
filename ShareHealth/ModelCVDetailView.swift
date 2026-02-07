import SwiftUI
import Charts

/// Shows detailed leave-one-out cross-validation results with scatter plot
struct ModelCVDetailView: View {
    let targetId: String
    let targetName: String

    // Pass captures directly to avoid @ObservedObject timing issues
    let captures: [StoredFaceCapture]

    @State private var cvResults: ModelCVResults?
    @State private var isLoading = true
    @State private var selectedPointIndex: Int? = nil
    @State private var showingPointDetail = false
    @State private var isScatterExpanded = false
    @Environment(\.dismiss) private var dismiss

    private let trainer = FaceHealthModelTrainer()
    @ObservedObject private var dataStore = FacialDataStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Computing LOO-CV...")
                            .padding()
                    } else if let results = cvResults {
                        statsSection(results)
                        scatterPlotSection(results)
                        featureImportanceSection
                        residualsSection(results)
                        interpretationSection(results)
                        modelInfoSection
                    } else {
                        Text("Insufficient data for analysis")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("\(targetName) Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadResults()
            }
            .sheet(isPresented: $showingPointDetail) {
                if let index = selectedPointIndex, let results = cvResults {
                    ScatterPointDetailView(
                        index: index,
                        results: results,
                        captures: captures,
                        targetName: targetName,
                        onDelete: { captureIds in
                            deleteCaptures(ids: captureIds)
                        }
                    )
                }
            }
        }
    }

    private func deleteCaptures(ids: [String]) {
        for id in ids {
            if let capture = dataStore.captures.first(where: { $0.id == id }) {
                try? dataStore.deleteCapture(capture)
            }
        }
        // Dismiss the detail sheet first
        showingPointDetail = false
        selectedPointIndex = nil

        // Wait for dataStore to reload, then recompute results
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = true
            self.reloadResultsFromDataStore()
        }
    }

    /// Reload results using the latest data from dataStore
    private func reloadResultsFromDataStore() {
        let currentCaptures = dataStore.captures
        let tid = targetId

        DispatchQueue.global(qos: .userInitiated).async {
            let results = self.trainer.getCVResults(for: tid, captures: currentCaptures)
            DispatchQueue.main.async {
                self.cvResults = results
                self.isLoading = false
            }
        }
    }

    // MARK: - Stats Section

    private func statsSection(_ results: ModelCVResults) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Leave-One-Out Cross-Validation")
                .font(.headline)

            Text("Each point is predicted using a model trained on all OTHER samples. This gives an honest estimate of predictive accuracy.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                StatCard(
                    title: "R (LOO-CV)",
                    value: String(format: "%.3f", results.correlation),
                    subtitle: correlationInterpretation(results.correlation),
                    color: colorForCorrelation(results.correlation)
                )

                StatCard(
                    title: "Samples",
                    value: "\(results.sampleCount)",
                    subtitle: "with data",
                    color: .blue
                )
            }

            HStack(spacing: 20) {
                StatCard(
                    title: "MAE",
                    value: formatValue(results.mae, for: targetId),
                    subtitle: "Mean Abs Error",
                    color: .orange
                )

                StatCard(
                    title: "RMSE",
                    value: formatValue(results.rmse, for: targetId),
                    subtitle: "Root Mean Sq Error",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Scatter Plot

    private func scatterPlotSection(_ results: ModelCVResults) -> some View {
        // Calculate axis range from actual data with padding
        let allValues = results.actuals + results.predictions
        let dataMin = allValues.min() ?? 0
        let dataMax = allValues.max() ?? 100
        let range = dataMax - dataMin
        let padding = range * 0.1  // 10% padding

        // Compute nice axis bounds
        let axisMin = max(0, dataMin - padding)  // Don't go below 0 for most metrics
        let axisMax = dataMax + padding

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Actual vs Predicted")
                    .font(.headline)
                Spacer()
                Button(action: { isScatterExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isScatterExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        Text(isScatterExpanded ? "Collapse" : "Expand")
                    }
                    .font(.caption2)
                    .foregroundColor(.blue)
                }
            }

            Text("Tap a point to view details")
                .font(.caption)
                .foregroundColor(.secondary)

            // Interactive scatter plot using overlay for tap detection
            ZStack {
                Chart {
                    // Perfect prediction line (diagonal)
                    LineMark(
                        x: .value("Predicted", axisMin),
                        y: .value("Actual", axisMin)
                    )
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))

                    LineMark(
                        x: .value("Predicted", axisMax),
                        y: .value("Actual", axisMax)
                    )
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))

                    // Data points - X is Predicted, Y is Actual
                    ForEach(Array(zip(results.actuals, results.predictions).enumerated()), id: \.offset) { index, pair in
                        PointMark(
                            x: .value("Predicted", pair.1),  // Predicted on X
                            y: .value("Actual", pair.0)      // Actual on Y
                        )
                        .foregroundStyle(selectedPointIndex == index ? Color.blue : colorForCorrelation(results.correlation))
                        .symbolSize(isScatterExpanded ? 200 : 120)
                    }
                }
                .chartXScale(domain: axisMin...axisMax)
                .chartYScale(domain: axisMin...axisMax)
                .chartXAxisLabel("Predicted \(unitForTarget(targetId))")
                .chartYAxisLabel("Actual \(unitForTarget(targetId))")
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                handleChartTap(at: location, proxy: proxy, geometry: geometry, results: results, axisMin: axisMin, axisMax: axisMax)
                            }
                    }
                }
            }
            .frame(height: isScatterExpanded ? 400 : 250)
            .animation(.easeInOut(duration: 0.3), value: isScatterExpanded)

            Text("Dashed line = perfect prediction. Points closer to the line = better predictions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, results: ModelCVResults, axisMin: Double, axisMax: Double) {
        // Find the closest point to the tap
        var closestIndex: Int? = nil
        var closestDistance: CGFloat = .infinity
        let tapThreshold: CGFloat = isScatterExpanded ? 50 : 40  // Larger threshold for easier tapping

        for (index, (actual, predicted)) in zip(results.actuals, results.predictions).enumerated() {
            // Calculate screen position of this point
            if let xPosition = proxy.position(forX: predicted),
               let yPosition = proxy.position(forY: actual) {
                let pointLocation = CGPoint(x: xPosition, y: yPosition)
                let distance = hypot(location.x - pointLocation.x, location.y - pointLocation.y)

                if distance < closestDistance && distance < tapThreshold {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }

        if let index = closestIndex {
            selectedPointIndex = index
            showingPointDetail = true
        }
    }

    // MARK: - Residuals Section

    private func residualsSection(_ results: ModelCVResults) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prediction Errors Over Time")
                .font(.headline)

            let errors = zip(results.actuals, results.predictions).map { $0 - $1 }
            let sortedData = zip(results.dates, errors).sorted { $0.0 < $1.0 }

            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))

                ForEach(Array(sortedData.enumerated()), id: \.offset) { index, pair in
                    BarMark(
                        x: .value("Date", pair.0, unit: .day),
                        y: .value("Error", pair.1)
                    )
                    .foregroundStyle(pair.1 >= 0 ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                }
            }
            .chartYAxisLabel("Error (Actual - Predicted)")
            .frame(height: 150)

            Text("Green = under-predicted, Red = over-predicted")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Feature Importance Section

    private var featureImportanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Predictive Features")
                .font(.headline)

            Text("Features with largest coefficients (most influence on prediction)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let importance = trainer.getFeatureImportance(for: targetId) {
                let topFeatures = Array(importance.prefix(8))
                let maxCoef = topFeatures.map { abs($0.coefficient) }.max() ?? 1

                ForEach(Array(topFeatures.enumerated()), id: \.offset) { index, feature in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        Text(feature.name)
                            .font(.caption)
                            .frame(width: 100, alignment: .leading)

                        GeometryReader { geo in
                            let width = geo.size.width * CGFloat(abs(feature.coefficient) / maxCoef)
                            let color: Color = feature.coefficient >= 0 ? .green : .red

                            HStack(spacing: 0) {
                                if feature.coefficient < 0 {
                                    Spacer()
                                    Rectangle()
                                        .fill(color.opacity(0.7))
                                        .frame(width: width / 2)
                                } else {
                                    Rectangle()
                                        .fill(color.opacity(0.7))
                                        .frame(width: width / 2)
                                    Spacer()
                                }
                            }
                        }
                        .frame(height: 12)

                        Text(String(format: "%.2f", feature.coefficient))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }

                HStack {
                    Circle().fill(Color.green.opacity(0.7)).frame(width: 10, height: 10)
                    Text("Positive: higher value → higher prediction")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 10, height: 10)
                    Text("Negative: higher value → lower prediction")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Model not trained")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Model Info Section

    private var modelInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Algorithm", value: "Ridge Regression (L2)")
                InfoRow(label: "Input Features", value: "24 facial metrics")
                InfoRow(label: "Regularization", value: "λ = 0.01")
                InfoRow(label: "Validation", value: "Leave-One-Out CV")
            }

            Text("All 24 input features come from facial analysis only. No health data is used as input — the model predicts health metrics purely from your face.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Interpretation Section

    private func interpretationSection(_ results: ModelCVResults) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interpretation")
                .font(.headline)

            let r = results.correlation
            let r2 = r * r

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("R = \(String(format: "%.3f", r)) means facial features explain about \(Int(r2 * 100))% of the variance in \(targetName.lowercased()).")
                        .font(.subheadline)
                }

                if r >= 0.5 {
                    HStack(alignment: .top) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("This is a moderate to strong correlation. Your face appears to reflect your \(targetName.lowercased()).")
                            .font(.subheadline)
                    }
                } else if r >= 0.3 {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("This is a weak to moderate correlation. Some signal exists, but predictions have significant uncertainty.")
                            .font(.subheadline)
                    }
                } else {
                    HStack(alignment: .top) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                        Text("This is a weak correlation. Either more data is needed, or facial features may not strongly predict this metric for you.")
                            .font(.subheadline)
                    }
                }

                if results.sampleCount < 20 {
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(.blue)
                        Text("With only \(results.sampleCount) samples, adding more captures may improve the model.")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func loadResults() {
        // Captures are passed directly, so just compute results
        // Use local copy to avoid any threading issues
        let capturesCopy = captures
        let tid = targetId

        DispatchQueue.global(qos: .userInitiated).async {
            let results = self.trainer.getCVResults(for: tid, captures: capturesCopy)
            DispatchQueue.main.async {
                self.cvResults = results
                self.isLoading = false
            }
        }
    }

    private func correlationInterpretation(_ r: Double) -> String {
        switch abs(r) {
        case 0.7...: return "Strong"
        case 0.5..<0.7: return "Moderate"
        case 0.3..<0.5: return "Weak"
        default: return "Very Weak"
        }
    }

    private func colorForCorrelation(_ r: Double) -> Color {
        switch abs(r) {
        case 0.5...: return .green
        case 0.3..<0.5: return .orange
        default: return .red
        }
    }

    private func formatValue(_ value: Double, for targetId: String) -> String {
        switch targetId {
        case "sleepScore":
            return String(format: "%.1f", value)
        case "hrv":
            return String(format: "%.1f ms", value)
        case "restingHR":
            return String(format: "%.1f bpm", value)
        default:
            return String(format: "%.2f", value)
        }
    }

    private func unitForTarget(_ targetId: String) -> String {
        switch targetId {
        case "sleepScore": return "(score)"
        case "hrv": return "(ms)"
        case "restingHR": return "(bpm)"
        default: return ""
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Scatter Point Detail View

/// Shows face images for a selected scatter plot point with option to delete
private struct ScatterPointDetailView: View {
    let index: Int
    let results: ModelCVResults
    let captures: [StoredFaceCapture]  // Initial captures (for reference)
    let targetName: String
    let onDelete: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = FacialDataStore.shared
    @State private var showingDeleteConfirmation = false

    private var captureIdsForPoint: [String] {
        guard index < results.captureIds.count else { return [] }
        return results.captureIds[index]
    }

    /// Use live data from dataStore to reflect deletions
    private var capturesForPoint: [StoredFaceCapture] {
        captureIdsForPoint.compactMap { id in
            dataStore.captures.first { $0.id == id }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date and values
                    dateAndValuesSection

                    // Face images
                    if !capturesForPoint.isEmpty {
                        facesSection
                    } else {
                        Text("No face images found for this day")
                            .foregroundColor(.secondary)
                            .padding()
                    }

                    // Delete button
                    if !capturesForPoint.isEmpty {
                        deleteSection
                    }
                }
                .padding()
            }
            .navigationTitle("Data Point Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete \(capturesForPoint.count) Capture(s)?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete(captureIdsForPoint)
                }
            } message: {
                Text("This will delete all face captures for this day. The model will be retrained automatically.")
            }
        }
    }

    private var dateAndValuesSection: some View {
        VStack(spacing: 16) {
            if index < results.dates.count {
                let date = results.dates[index]
                let formatter = DateFormatter()
                let _ = formatter.dateStyle = .long

                Text(formatter.string(from: date))
                    .font(.headline)
            }

            HStack(spacing: 30) {
                VStack {
                    Text("Actual")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if index < results.actuals.count {
                        Text(String(format: "%.1f", results.actuals[index]))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }

                VStack {
                    Text("Predicted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if index < results.predictions.count {
                        Text(String(format: "%.1f", results.predictions[index]))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }

                VStack {
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if index < results.actuals.count && index < results.predictions.count {
                        let error = results.actuals[index] - results.predictions[index]
                        Text(String(format: "%+.1f", error))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(error >= 0 ? .orange : .purple)
                    }
                }
            }

            if capturesForPoint.count > 1 {
                Text("\(capturesForPoint.count) captures averaged for this day")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var facesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Face Captures")
                    .font(.headline)
                Spacer()
                if capturesForPoint.count > 1 {
                    Text("Swipe to delete individual")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(capturesForPoint) { capture in
                FaceCaptureRowWithDelete(
                    capture: capture,
                    onDelete: {
                        onDelete([capture.id])
                    }
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var deleteSection: some View {
        VStack(spacing: 12) {
            if capturesForPoint.count > 1 {
                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All \(capturesForPoint.count) Captures for This Day")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete This Capture")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }
}

// MARK: - Face Capture Row

private struct FaceCaptureRow: View {
    let capture: StoredFaceCapture
    @State private var image: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                    .overlay(ProgressView())
            }

            VStack(alignment: .leading, spacing: 4) {
                let formatter = DateFormatter()
                let _ = formatter.timeStyle = .short

                Text(formatter.string(from: capture.captureDate))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let metrics = capture.metrics {
                    HStack(spacing: 8) {
                        Label("\(Int(metrics.healthIndicators.alertnessScore))", systemImage: "eye")
                        Label("\(Int(metrics.healthIndicators.smileScore))", systemImage: "face.smiling")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if capture.hasHealthData {
                    Label("Health data attached", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("No health data", systemImage: "heart.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let loaded = capture.loadImage() {
                // Create thumbnail
                let size = CGSize(width: 160, height: 160)
                UIGraphicsBeginImageContextWithOptions(size, false, 0)
                loaded.draw(in: CGRect(origin: .zero, size: size))
                let thumb = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                DispatchQueue.main.async {
                    self.image = thumb
                }
            }
        }
    }
}

// MARK: - Face Capture Row With Delete

private struct FaceCaptureRowWithDelete: View {
    let capture: StoredFaceCapture
    let onDelete: () -> Void

    @State private var image: UIImage? = nil
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                    .overlay(ProgressView())
            }

            VStack(alignment: .leading, spacing: 4) {
                let formatter = DateFormatter()
                let _ = formatter.timeStyle = .short

                Text(formatter.string(from: capture.captureDate))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let metrics = capture.metrics {
                    HStack(spacing: 8) {
                        Label("\(Int(metrics.healthIndicators.alertnessScore))", systemImage: "eye")
                        Label("\(Int(metrics.healthIndicators.smileScore))", systemImage: "face.smiling")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if capture.hasHealthData {
                    Label("Health data attached", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("No health data", systemImage: "heart.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // Delete button
            Button(action: { showingDeleteConfirmation = true }) {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .onAppear {
            loadImage()
        }
        .alert("Delete This Capture?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will delete this face capture. The model will be retrained automatically.")
        }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let loaded = capture.loadImage() {
                // Create thumbnail
                let size = CGSize(width: 160, height: 160)
                UIGraphicsBeginImageContextWithOptions(size, false, 0)
                loaded.draw(in: CGRect(origin: .zero, size: size))
                let thumb = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                DispatchQueue.main.async {
                    self.image = thumb
                }
            }
        }
    }
}

#Preview {
    ModelCVDetailView(targetId: "sleepScore", targetName: "Sleep Score", captures: [])
}
