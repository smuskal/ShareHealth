import SwiftUI
import HealthKit

struct WelcomeView: View {
    let onAuthorized: () -> Void
    @AppStorage("hasSeenGlobalMedicalDisclaimer") private var hasSeenGlobalMedicalDisclaimer = false
    @StateObject private var stepManager = StepManager()
    @StateObject private var healthExporter = HealthDataExporter()
    @State private var isRequesting = false
    @State private var showingMedicalDisclaimer = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to ShareHealth")
                .font(.largeTitle)
                .padding(.bottom, 20)

            Text("Export and share your Apple Health data!")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("This app needs access to Apple Health to read your health metrics for export, and to read/write step data for sharing.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Data we'll access:")
                    .font(.headline)
                    .padding(.bottom, 4)

                HStack { Image(systemName: "figure.walk").foregroundColor(.blue); Text("Activity & Steps (read & write)") }
                HStack { Image(systemName: "heart.fill").foregroundColor(.red); Text("Heart Rate & Vitals") }
                HStack { Image(systemName: "bed.double.fill").foregroundColor(.purple); Text("Sleep Analysis") }
                HStack { Image(systemName: "fork.knife").foregroundColor(.orange); Text("Nutrition Data") }
                HStack { Image(systemName: "lungs.fill").foregroundColor(.cyan); Text("Respiratory Metrics") }
                HStack { Image(systemName: "scalemass.fill").foregroundColor(.green); Text("Body Measurements") }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            Text("Important: Enable both READ and WRITE for Steps to share and receive step data with friends.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if isRequesting {
                ProgressView()
                    .padding()
                Text("Requesting HealthKit access...")
                    .foregroundColor(.secondary)
            } else {
                Button(action: requestAccess) {
                    Text("Enable HealthKit Access")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingMedicalDisclaimer) {
            NavigationStack {
                ScrollView {
                    Text("""
Medical Disclaimer

ShareHealth provides informational and educational content only. It does not provide medical advice, diagnosis, or treatment, and it is not a medical device.

Do not use this app as a substitute for professional judgment. Always consult a licensed physician or other qualified healthcare provider before making medical decisions or changing medications, treatment plans, diet, or activity.

If you think you may have a medical emergency, call 911 immediately.
""")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Before You Continue")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("I Understand") {
                            hasSeenGlobalMedicalDisclaimer = true
                            showingMedicalDisclaimer = false
                            HealthKitManager.shared.setAuthorized(true)
                            onAuthorized()
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func requestAccess() {
        isRequesting = true

        // Request full health data authorization for export functionality
        healthExporter.requestFullAuthorization { success in
            // Also request step write permission for sharing functionality
            stepManager.requestAuthorization { stepSuccess in
                DispatchQueue.main.async {
                    isRequesting = false
                    if success || stepSuccess {
                        print("✅ [WELCOME] HealthKit access granted")
                        UserDefaults.standard.set(true, forKey: "healthExportAuthorized")
                        if hasSeenGlobalMedicalDisclaimer {
                            HealthKitManager.shared.setAuthorized(true)
                            onAuthorized()
                        } else {
                            showingMedicalDisclaimer = true
                        }
                    } else {
                        print("❌ [WELCOME] HealthKit access denied")
                    }
                }
            }
        }
    }
}
