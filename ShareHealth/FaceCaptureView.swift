import SwiftUI
import AVFoundation

/// A view that presents a front-facing camera for capturing a face image
struct FaceCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()

    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var capturedImage: UIImage? = nil
    @State private var showingPreview = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if showingPreview, let image = capturedImage {
                    previewView(image: image)
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
                    Text(showingPreview ? "Preview" : "Take Photo")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    // MARK: - Camera View

    private var cameraView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Camera preview
            CameraPreviewView(session: cameraManager.session)
                .aspectRatio(3/4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .padding(.horizontal, 20)

            Spacer()

            // Instructions
            Text("Position your face in the frame")
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

    // MARK: - Preview View

    private func previewView(image: UIImage) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Image preview
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .padding(.horizontal, 20)

            Spacer()

            // Action buttons
            HStack(spacing: 40) {
                // Retake button
                Button(action: retakePhoto) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 24))
                        Text("Retake")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                }

                // Use photo button
                Button(action: usePhoto) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                        Text("Use Photo")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    .frame(width: 80)
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    private func capturePhoto() {
        cameraManager.capturePhoto { image in
            DispatchQueue.main.async {
                self.capturedImage = image
                self.showingPreview = true
            }
        }
    }

    private func retakePhoto() {
        capturedImage = nil
        showingPreview = false
        cameraManager.startSession()
    }

    private func usePhoto() {
        guard let image = capturedImage else { return }
        cameraManager.stopSession()
        onCapture(image)
        dismiss()
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    @Published var isReady = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?

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

        // Mirror the image horizontally to match what the user sees in preview
        let mirroredImage = UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: .leftMirrored)
        captureCompletion?(mirroredImage)
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
        onCapture: { _ in },
        onCancel: { }
    )
}
