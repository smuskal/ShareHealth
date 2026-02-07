import SwiftUI
import AVFoundation

/// A view that presents a front-facing camera for capturing a face image with analysis
struct FaceCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var analysisCoordinator = FaceAnalysisCoordinator()

    let onCapture: (UIImage, FacialMetrics?) -> Void
    let onCancel: () -> Void

    @State private var capturedImage: UIImage? = nil
    @State private var showingPreview = false
    @State private var showingAnalysisResults = false
    @State private var analyzedMetrics: FacialMetrics? = nil

    // Real-time face detection state
    @State private var isFaceDetected = false
    @State private var faceQuality: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if showingAnalysisResults, let image = capturedImage, let metrics = analyzedMetrics {
                    // Show analysis results
                    FaceAnalysisResultView(
                        image: image,
                        metrics: metrics,
                        onUsePhoto: usePhoto,
                        onRetake: retakePhoto
                    )
                } else if showingPreview, let image = capturedImage {
                    // Show preview while analyzing
                    analyzingPreviewView(image: image)
                } else {
                    cameraView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cameraManager.stopSession()
                        onCancel()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            cameraManager.startSession()
            cameraManager.onFaceDetection = { detected, quality in
                self.isFaceDetected = detected
                self.faceQuality = quality
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    private var navigationTitle: String {
        if showingAnalysisResults {
            return "Analysis Results"
        } else if analysisCoordinator.isAnalyzing {
            return "Analyzing..."
        } else if showingPreview {
            return "Processing"
        } else {
            return "Take Photo"
        }
    }

    // MARK: - Camera View

    private var cameraView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Camera preview with overlay
            ZStack {
                CameraPreviewView(session: cameraManager.session)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(frameColor, lineWidth: 2)
                    )

                // Face detection overlay
                FaceAnalysisOverlayView(
                    isFaceDetected: isFaceDetected,
                    faceQuality: faceQuality,
                    isAnalyzing: false,
                    analysisProgress: 0
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 20)

            Spacer()

            // Instructions
            Text(instructionText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .padding(.bottom, 20)

            // Capture button
            Button(action: capturePhoto) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)

                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }
            }
            .disabled(!cameraManager.isReady)
            .opacity(cameraManager.isReady ? 1.0 : 0.5)
            .padding(.bottom, 40)
        }
    }

    private var frameColor: Color {
        if isFaceDetected {
            return faceQuality > 0.7 ? .green.opacity(0.8) : .yellow.opacity(0.8)
        }
        return .white.opacity(0.3)
    }

    private var instructionText: String {
        if !isFaceDetected {
            return "Position your face in the frame"
        } else if faceQuality < 0.7 {
            return "Hold steady for better quality"
        } else {
            return "Ready to capture"
        }
    }

    // MARK: - Analyzing Preview View

    private func analyzingPreviewView(image: UIImage) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Image preview
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .blur(radius: 3)

                // Analysis progress overlay
                AnalysisProgressOverlay(
                    progress: analysisCoordinator.analysisProgress,
                    currentStep: analysisCoordinator.currentStep,
                    onCancel: {
                        retakePhoto()
                    }
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            // Status text
            Text(analysisCoordinator.currentStep)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    private func capturePhoto() {
        cameraManager.capturePhoto { image in
            DispatchQueue.main.async {
                guard let image = image else { return }

                self.capturedImage = image
                self.showingPreview = true

                // Start analysis
                self.analysisCoordinator.analyze(image: image) { metrics in
                    self.analyzedMetrics = metrics
                    self.showingAnalysisResults = true
                }
            }
        }
    }

    private func retakePhoto() {
        capturedImage = nil
        analyzedMetrics = nil
        showingPreview = false
        showingAnalysisResults = false
        cameraManager.startSession()
    }

    private func usePhoto() {
        guard let image = capturedImage else { return }
        cameraManager.stopSession()
        onCapture(image, analyzedMetrics)
        dismiss()
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    @Published var isReady = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private let faceAnalyzer = MediaPipeFaceAnalyzer()

    // Face detection callback
    var onFaceDetection: ((Bool, Double) -> Void)?

    private let processingQueue = DispatchQueue(label: "com.sharehealth.facedetection", qos: .userInteractive)
    private var lastProcessingTime = Date()
    private let processingInterval: TimeInterval = 0.1 // 10 FPS for face detection

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Find front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not available")
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            // Add video output for real-time face detection
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
        } catch {
            print("Failed to setup camera: \(error.localizedDescription)")
            session.commitConfiguration()
        }
    }

    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isReady = true
            }
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isReady = false
            }
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            captureCompletion?(nil)
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            captureCompletion?(nil)
            return
        }

        // Apply horizontal flip for front camera captures.
        // The front camera captures a non-mirrored image by default, but users expect
        // the saved image to match the mirrored preview they see (like a mirror).
        // Flipping ensures text on clothing etc. reads correctly in stored images.
        let flippedImage = image.flippedHorizontally()
        captureCompletion?(flippedImage)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle processing
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval else { return }
        lastProcessingTime = now

        // Perform face detection
        faceAnalyzer.detectFace(in: sampleBuffer) { [weak self] detected, quality in
            self?.onFaceDetection?(detected, quality)
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

#Preview {
    FaceCaptureView(
        onCapture: { _, _ in },
        onCancel: { }
    )
}
