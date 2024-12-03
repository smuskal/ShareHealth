import SwiftUI
import HealthKit

struct WelcomeView: View {
    let onAuthorized: () -> Void
    @StateObject private var stepManager = StepManager()
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to ShareSteps")
                .font(.largeTitle)
                .padding(.bottom, 20)
            
            Text("Share your daily step counts with friends and family!")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("ShareSteps needs access to Apple Health to read and write step data.")
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
    }
    
    private func requestAccess() {
        isRequesting = true
        stepManager.requestAuthorization { success in
            DispatchQueue.main.async {
                isRequesting = false
                if success {
                    print("✅ [WELCOME] HealthKit access granted")
                    onAuthorized()
                } else {
                    print("❌ [WELCOME] HealthKit access denied")
                }
            }
        }
    }
}
