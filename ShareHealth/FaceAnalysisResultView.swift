import SwiftUI

/// Displays facial analysis results after capture
struct FaceAnalysisResultView: View {
    let image: UIImage
    let metrics: FacialMetrics
    let onUsePhoto: () -> Void
    let onRetake: () -> Void

    @State private var showingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            ScrollView {
                VStack(spacing: 20) {
                    // Face image preview
                    imagePreview

                    // Health indicators
                    healthIndicatorsSection

                    // Device capability info
                    capabilityInfo

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingDetails) {
            FacialMetricsDetailView(metrics: metrics)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Facial Analysis")
                .font(.headline)
                .padding(.top, 16)

            Text(metrics.analysisMode == .visionAndARKit ? "Full Analysis" : "Basic Analysis")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Health Indicators

    private var healthIndicatorsSection: some View {
        VStack(spacing: 16) {
            // Main scores grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ScoreCard(
                    title: "Alertness",
                    score: metrics.healthIndicators.alertnessScore,
                    description: metrics.healthIndicators.alertnessDescription,
                    icon: "eye.fill",
                    color: alertnessColor
                )

                ScoreCard(
                    title: "Tension",
                    score: metrics.healthIndicators.tensionScore,
                    description: metrics.healthIndicators.tensionDescription,
                    icon: "bolt.fill",
                    color: tensionColor
                )

                ScoreCard(
                    title: "Mood",
                    score: metrics.healthIndicators.smileScore,
                    description: metrics.healthIndicators.moodDescription,
                    icon: "face.smiling.fill",
                    color: moodColor
                )

                ScoreCard(
                    title: "Symmetry",
                    score: metrics.healthIndicators.facialSymmetry,
                    description: metrics.healthIndicators.symmetryDescription,
                    icon: "arrow.left.and.right",
                    color: symmetryColor
                )
            }

            // Reliability indicator
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(reliabilityColor)

                Text("Capture Quality: \(metrics.healthIndicators.reliabilityDescription)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(metrics.healthIndicators.captureReliabilityScore))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(reliabilityColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // View details button
            Button(action: { showingDetails = true }) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text("View Detailed Metrics")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Capability Info

    private var capabilityInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: metrics.analysisMode == .visionAndARKit ? "face.smiling" : "eye")
                .foregroundColor(.secondary)

            Text(DeviceCapabilities.capabilityDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Retake button
            Button(action: onRetake) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Retake")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Use photo button
            Button(action: onUsePhoto) {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Use Photo")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
        .padding(.top, 8)
    }

    // MARK: - Color Helpers

    private var alertnessColor: Color {
        switch metrics.healthIndicators.alertnessScore {
        case 70...100: return .green
        case 40..<70: return .orange
        default: return .red
        }
    }

    private var tensionColor: Color {
        switch metrics.healthIndicators.tensionScore {
        case 0..<30: return .green
        case 30..<60: return .orange
        default: return .red
        }
    }

    private var moodColor: Color {
        switch metrics.healthIndicators.smileScore {
        case 60...100: return .green
        case 40..<60: return .yellow
        default: return .orange
        }
    }

    private var symmetryColor: Color {
        switch metrics.healthIndicators.facialSymmetry {
        case 80...100: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    private var reliabilityColor: Color {
        switch metrics.healthIndicators.captureReliabilityScore {
        case 70...100: return .green
        case 40..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - Score Card Component

struct ScoreCard: View {
    let title: String
    let score: Double
    let description: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("\(Int(score))")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * score / 100, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Detailed Metrics View

struct FacialMetricsDetailView: View {
    let metrics: FacialMetrics
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Health Indicators Section
                Section("Health Indicators") {
                    MetricRow(label: "Alertness", value: metrics.healthIndicators.alertnessScore, unit: "%")
                    MetricRow(label: "Tension", value: metrics.healthIndicators.tensionScore, unit: "%")
                    MetricRow(label: "Smile/Mood", value: metrics.healthIndicators.smileScore, unit: "%")
                    MetricRow(label: "Symmetry", value: metrics.healthIndicators.facialSymmetry, unit: "%")
                    MetricRow(label: "Capture Quality", value: metrics.healthIndicators.captureReliabilityScore, unit: "%")
                }

                // Vision Metrics Section
                if let vision = metrics.visionMetrics {
                    Section("Vision Analysis") {
                        MetricRow(label: "Face Quality", value: vision.faceQuality * 100, unit: "%")
                        MetricRow(label: "Left Eye Openness", value: vision.leftEyeOpenness * 100, unit: "%")
                        MetricRow(label: "Right Eye Openness", value: vision.rightEyeOpenness * 100, unit: "%")
                        MetricRow(label: "Head Roll", value: vision.rollDegrees, unit: "°")
                        MetricRow(label: "Head Pitch", value: vision.pitchDegrees, unit: "°")
                        MetricRow(label: "Head Yaw", value: vision.yawDegrees, unit: "°")
                        MetricRow(label: "Landmarks Detected", value: Double(vision.landmarkCount), unit: "")
                    }
                }

                // ARKit Metrics Section
                if let arkit = metrics.arkitMetrics {
                    Section("Expression Analysis") {
                        MetricRow(label: "Smile Left", value: arkit.mouthSmileLeft * 100, unit: "%")
                        MetricRow(label: "Smile Right", value: arkit.mouthSmileRight * 100, unit: "%")
                        MetricRow(label: "Frown Left", value: arkit.mouthFrownLeft * 100, unit: "%")
                        MetricRow(label: "Frown Right", value: arkit.mouthFrownRight * 100, unit: "%")
                        MetricRow(label: "Brow Down Left", value: arkit.browDownLeft * 100, unit: "%")
                        MetricRow(label: "Brow Down Right", value: arkit.browDownRight * 100, unit: "%")
                        MetricRow(label: "Brow Inner Up", value: arkit.browInnerUp * 100, unit: "%")
                    }

                    Section("Eye Tracking") {
                        MetricRow(label: "Eye Blink Left", value: arkit.eyeBlinkLeft * 100, unit: "%")
                        MetricRow(label: "Eye Blink Right", value: arkit.eyeBlinkRight * 100, unit: "%")
                        MetricRow(label: "Eye Wide Left", value: arkit.eyeWideLeft * 100, unit: "%")
                        MetricRow(label: "Eye Wide Right", value: arkit.eyeWideRight * 100, unit: "%")
                        MetricRow(label: "Eye Squint Left", value: arkit.eyeSquintLeft * 100, unit: "%")
                        MetricRow(label: "Eye Squint Right", value: arkit.eyeSquintRight * 100, unit: "%")
                    }

                    Section("Jaw & Mouth") {
                        MetricRow(label: "Jaw Open", value: arkit.jawOpen * 100, unit: "%")
                        MetricRow(label: "Jaw Forward", value: arkit.jawForward * 100, unit: "%")
                        MetricRow(label: "Mouth Pucker", value: arkit.mouthPucker * 100, unit: "%")
                        MetricRow(label: "Cheek Puff", value: arkit.cheekPuff * 100, unit: "%")
                    }
                }

                // Metadata Section
                Section("Capture Info") {
                    HStack {
                        Text("Timestamp")
                        Spacer()
                        Text(formatDate(metrics.captureTimestamp))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Analysis Mode")
                        Spacer()
                        Text(metrics.analysisMode.rawValue)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(metrics.analysisVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Detailed Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Metric Row Component

struct MetricRow: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(formatValue(value) + unit)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Preview

#Preview {
    FaceAnalysisResultView(
        image: UIImage(systemName: "person.fill")!,
        metrics: FacialMetrics(
            analysisMode: .visionAndARKit,
            healthIndicators: FacialHealthIndicators(
                alertnessScore: 72.5,
                tensionScore: 25.0,
                smileScore: 65.0,
                facialSymmetry: 94.2,
                captureReliabilityScore: 88.0
            ),
            visionMetrics: VisionFaceMetrics(
                faceQuality: 0.95,
                roll: 0.02,
                pitch: -0.05,
                yaw: 0.03,
                leftEyeOpenness: 0.78,
                rightEyeOpenness: 0.75,
                faceBoundingBox: CodableBoundingBox(CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
                landmarkCount: 76
            )
        ),
        onUsePhoto: {},
        onRetake: {}
    )
}
