import SwiftUI
import HealthKit

struct PendingImportData {
    let url: URL
    let uuid: String
    let importDate: Date // Added the importDate property
}

@main
struct ShareStepsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var importedSteps: Int = 0
    @State private var showingImportDetails = false
    @State private var pendingImportData: PendingImportData?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var shouldFetchHealthData = true
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var pendingURL: URL?
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !healthKitManager.isAuthorized {
                    WelcomeView {
                        healthKitManager.setAuthorized(true)
                        // Process any pending URL after authorization
                        if let url = pendingURL {
                            handleIncomingURL(url: url)
                            pendingURL = nil
                        }
                    }
                } else {
                    MainMenuView(importedSteps: $importedSteps, shouldFetchHealthData: shouldFetchHealthData)
                }
            }
            .sheet(isPresented: $showingImportDetails, onDismiss: {
                // After import sheet is dismissed, enable HealthKit fetching
                shouldFetchHealthData = true
                
                // Post notification to trigger data refresh if needed
                if let date = pendingImportData?.importDate {
                    NotificationCenter.default.post(
                        name: .refreshStepsData,
                        object: nil,
                        userInfo: ["date": date]
                    )
                }
            }) {
                if let pending = pendingImportData {
                    ImportDetailsView(
                        pendingData: pending,
                        onAccept: { jsonData, isAdding in
                            print("\n🔄 [APP] User chose to add steps")
                            modifyHealthKitData(jsonData: jsonData)
                        }
                    )
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                print("\n🚀 [APP] App appearing")
                NotificationCenter.default.addObserver(
                    forName: .handleIncomingURL,
                    object: nil,
                    queue: .main
                ) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        print("🔗 [APP] Processing URL: \(url.absoluteString)")
                        if healthKitManager.isAuthorized {
                            shouldFetchHealthData = false
                            handleIncomingURL(url: url)
                        } else {
                            print("⏳ [APP] Waiting for HealthKit authorization")
                            pendingURL = url
                        }
                    }
                }
            }
            .onOpenURL { url in
                print("\n🎯 [SWIFTUI] Direct URL handler called!")
                print("📥 [SWIFTUI] Received URL: \(url.absoluteString)")
                
                // Disable HealthKit fetching when processing URL
                shouldFetchHealthData = false
                
                if healthKitManager.isAuthorized {
                    handleIncomingURL(url: url)
                } else {
                    print("⏳ [APP] Waiting for HealthKit authorization")
                    pendingURL = url
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                print("\n🟢 [APP] Scene phase changed to active")
                if healthKitManager.isAuthorized {
                    if let url = pendingURL {
                        print("🔄 [APP] Processing pending URL")
                        // Disable HealthKit fetching for background activation
                        shouldFetchHealthData = false
                        handleIncomingURL(url: url)
                        pendingURL = nil
                    }
                }
            case .inactive:
                print("\n🟡 [APP] Scene phase changed to inactive")
            case .background:
                print("\n⚫️ [APP] Scene phase changed to background")
            @unknown default:
                print("\n❓ [APP] Scene phase changed to unknown state")
            }
        }
    }

    private func handleIncomingURL(url: URL) {
        print("\n🔗 [URL] Processing: \(url.absoluteString)")
        
        guard let uuid = url.host else {
            showError("Invalid URL format")
            return
        }

        let downloadURL = "https://molseek.com/sharedSteps/uploads/\(uuid)"
        guard let processURL = URL(string: downloadURL) else {
            showError("Invalid download URL")
            return
        }

        // Initialize PendingImportData with importDate as current date
        pendingImportData = PendingImportData(url: processURL, uuid: uuid, importDate: Date())
        showingImportDetails = true
    }

    private func modifyHealthKitData(jsonData: [String: Any]) {
            guard let dateStr = jsonData["date"] as? String,
                  let hourlySteps = jsonData["hourly_steps"] as? [String: Int],
                  let totalSteps = jsonData["steps"] as? Int else {
                showError("Invalid JSON data structure")
                return
            }
            
            if let notes = jsonData["notes"] as? String {
                UserDefaults.standard.saveNotes(notes, forDate: dateStr)
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let date = dateFormatter.date(from: dateStr) else {
                showError("Invalid date format")
                return
            }

            print("📅 [APP] Processing data for date: \(dateStr)")
            
            let stepManager = StepManager()
            stepManager.modifySteps(for: date, steps: hourlySteps) { success, message in
                DispatchQueue.main.async {
                    if success {
                        // Wait a moment for server to update total
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            NotificationCenter.default.post(
                                name: .refreshStepsData,
                                object: nil,
                                userInfo: ["date": date]
                            )
                            
                            // Notify ContentView to refresh total steps
                            NotificationCenter.default.post(name: .StepData.updated, object: nil)
                        }
                        
                        self.showSuccessAlert(message: message ?? "Successfully imported \(totalSteps) steps")
                    } else {
                        self.showError(message ?? "Failed to import steps")
                    }
                }
            }
        }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showingError = true
        }
    }

    private func showSuccessAlert(message: String) {
        DispatchQueue.main.async {
            if let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?
                .windows
                .first?
                .rootViewController {
                let alert = UIAlertController(
                    title: "Success",
                    message: message,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                rootVC.present(alert, animated: true)
            }
        }
    }
}
