import SwiftUI

/// Real-time overlay showing face detection status during camera preview
struct FaceAnalysisOverlayView: View {
    let isFaceDetected: Bool
    let faceQuality: Double
    let isAnalyzing: Bool
    let analysisProgress: Double

    var body: some View {
        VStack {
            // Top status indicator
            HStack(spacing: 8) {
                if isAnalyzing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.white)

                    if isFaceDetected {
                        Spacer()
                        QualityIndicator(quality: faceQuality)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .padding(.top, 8)

            Spacer()

            // Bottom guidance
            if !isAnalyzing {
                Text(guidanceText)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
                    .padding(.bottom, 16)
            }
        }
    }

    private var statusColor: Color {
        if isFaceDetected {
            return faceQuality > 0.7 ? .green : .yellow
        }
        return .red
    }

    private var statusText: String {
        if isFaceDetected {
            return faceQuality > 0.7 ? "Face detected" : "Adjust position"
        }
        return "No face detected"
    }

    private var guidanceText: String {
        if !isFaceDetected {
            return "Position your face in the frame"
        } else if faceQuality < 0.5 {
            return "Move closer and face the camera directly"
        } else if faceQuality < 0.7 {
            return "Hold steady for better quality"
        } else {
            return "Ready to capture"
        }
    }
}

// MARK: - Quality Indicator

struct QualityIndicator: View {
    let quality: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Double(index + 1) / 3.0
        if quality >= threshold {
            if quality > 0.7 {
                return .green
            } else if quality > 0.4 {
                return .yellow
            } else {
                return .red
            }
        }
        return .gray.opacity(0.5)
    }

    private func barHeight(for index: Int) -> CGFloat {
        CGFloat(8 + index * 4)
    }
}

// MARK: - Analysis Progress Overlay

struct AnalysisProgressOverlay: View {
    let progress: Double
    let currentStep: String
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Progress circle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                if progress >= 1.0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }

            // Step text
            Text(currentStep)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Cancel button
            if let onCancel = onCancel, progress < 1.0 {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 8)
            }
        }
        .padding(32)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
    }
}

// MARK: - Face Frame Guide

struct FaceFrameGuide: View {
    let isFaceDetected: Bool
    let faceQuality: Double

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.7
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Oval guide
                Ellipse()
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: 3, dash: isFaceDetected ? [] : [10, 5]))
                    .frame(width: size * 0.8, height: size)
                    .position(center)

                // Corner indicators
                ForEach(0..<4) { corner in
                    CornerBracket(corner: corner, color: strokeColor)
                        .frame(width: 30, height: 30)
                        .position(cornerPosition(for: corner, in: geometry.size, ovalSize: CGSize(width: size * 0.8, height: size)))
                }
            }
        }
    }

    private var strokeColor: Color {
        if isFaceDetected {
            return faceQuality > 0.7 ? .green : .yellow
        }
        return .white.opacity(0.5)
    }

    private func cornerPosition(for corner: Int, in size: CGSize, ovalSize: CGSize) -> CGPoint {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let halfWidth = ovalSize.width / 2
        let halfHeight = ovalSize.height / 2

        switch corner {
        case 0: return CGPoint(x: centerX - halfWidth, y: centerY - halfHeight) // Top left
        case 1: return CGPoint(x: centerX + halfWidth, y: centerY - halfHeight) // Top right
        case 2: return CGPoint(x: centerX - halfWidth, y: centerY + halfHeight) // Bottom left
        case 3: return CGPoint(x: centerX + halfWidth, y: centerY + halfHeight) // Bottom right
        default: return .zero
        }
    }
}

// MARK: - Corner Bracket

struct CornerBracket: View {
    let corner: Int
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let length: CGFloat = 15

                switch corner {
                case 0: // Top left
                    path.move(to: CGPoint(x: 0, y: length))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: length, y: 0))
                case 1: // Top right
                    path.move(to: CGPoint(x: geometry.size.width - length, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: length))
                case 2: // Bottom left
                    path.move(to: CGPoint(x: 0, y: geometry.size.height - length))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: length, y: geometry.size.height))
                case 3: // Bottom right
                    path.move(to: CGPoint(x: geometry.size.width - length, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - length))
                default:
                    break
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

// MARK: - Previews

#Preview("Face Detected") {
    ZStack {
        Color.black

        FaceAnalysisOverlayView(
            isFaceDetected: true,
            faceQuality: 0.85,
            isAnalyzing: false,
            analysisProgress: 0
        )
    }
}

#Preview("No Face") {
    ZStack {
        Color.black

        FaceAnalysisOverlayView(
            isFaceDetected: false,
            faceQuality: 0,
            isAnalyzing: false,
            analysisProgress: 0
        )
    }
}

#Preview("Analyzing") {
    ZStack {
        Color.black

        AnalysisProgressOverlay(
            progress: 0.65,
            currentStep: "Analyzing expressions...",
            onCancel: {}
        )
    }
}

#Preview("Face Guide") {
    ZStack {
        Color.black

        FaceFrameGuide(isFaceDetected: true, faceQuality: 0.8)
    }
}
