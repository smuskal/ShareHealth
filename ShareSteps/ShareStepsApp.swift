import SwiftUI
import HealthKit

@main
struct ShareStepsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var importedSteps: Int = 0
    @State private var showingImportDetails = false
    @State private var importData: [String: Any]?
    @State private var showingError = false
    @State private var errorMessage = ""
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
                    ContentView(importedSteps: $importedSteps)
                }
            }
            .sheet(isPresented: $showingImportDetails) {
                if let data = importData {
                    ImportDetailsView(
                        steps: data["steps"] as? Int ?? 0,
                        date: data["date"] as? String ?? "",
                        sender: data["sender"] as? String ?? "",
                        notes: data["notes"] as? String,
                        jsonData: data
                    ) { jsonData, isAdding in
                        print("\n🔄 [APP] User chose to add steps")
                        modifyHealthKitData(jsonData: jsonData)
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                print("\n🚀 [APP] App appearing")
                setupURLHandling()
            }
            .onOpenURL { url in
                print("\n🎯 [SWIFTUI] Direct URL handler called!")
                print("📥 [SWIFTUI] Received URL: \(url.absoluteString)")
                
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
    
    private func setupURLHandling() {
        print("\n📡 [APP] Setting up URL notification observer")
        NotificationCenter.default.addObserver(
            forName: .handleIncomingURL,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                print("🔗 [APP] Processing URL: \(url.absoluteString)")
                if healthKitManager.isAuthorized {
                    handleIncomingURL(url: url)
                } else {
                    print("⏳ [APP] Waiting for HealthKit authorization")
                    pendingURL = url
                }
            }
        }
    }

    private func handleIncomingURL(url: URL) {
        print("\n🔗 [URL] Processing: \(url.absoluteString)")
        
        // Reset any existing sheet state
        showingImportDetails = false
        importData = nil
        
        // Process the URL immediately
        processURL(url)
    }
    
    private func processURL(_ url: URL) {
        guard let uuid = url.host else {
            showError("Invalid URL format")
            return
        }

        let downloadURLString = "https://molseek.com/sharedSteps/uploads/\(uuid)"
        guard let downloadURL = URL(string: downloadURLString) else {
            showError("Invalid download URL")
            return
        }

        downloadAndProcessURL(downloadURL)
    }

    private func downloadAndProcessURL(_ url: URL) {
            print("[URL] Downloading from: \(url.absoluteString)")
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ [URL] Download failed: \(error.localizedDescription)")
                        self.showError("Download failed")
                        return
                    }
                    
                    guard let data = data else {
                        print("❌ [URL] No data received")
                        self.showError("No data received")
                        return
                    }

                    do {
                        let json = try JSONSerialization.jsonObject(with: data)
                        if let jsonDict = json as? [String: Any] {
                            print("✅ [URL] Successfully parsed JSON")
                            self.importData = jsonDict
                            
                            // Force show the sheet after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.showingImportDetails = true
                            }
                            
                            // Also set up a backup timer in case the first attempt fails
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if !self.showingImportDetails {
                                    print("⚠️ [URL] Retry showing import details")
                                    self.showingImportDetails = true
                                }
                            }
                        } else {
                            print("❌ [URL] JSON is not a dictionary")
                            self.showError("Invalid data format")
                        }
                    } catch {
                        print("❌ [URL] Parse error: \(error)")
                        if let dataString = String(data: data, encoding: .utf8) {
                            print("❌ [URL] Raw data received: \(dataString)")
                        }
                        self.showError("Failed to parse data")
                    }
                }
            }.resume()
        }

    private func modifyHealthKitData(jsonData: [String: Any]) {
        guard let dateStr = jsonData["date"] as? String,
              let hourlySteps = jsonData["hourly_steps"] as? [String: Int],
              let totalSteps = jsonData["steps"] as? Int else {
            showError("Invalid JSON data structure")
            return
        }
        
        // Save any notes that came with the import
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
        stepManager.modifySteps(
            for: date,
            steps: hourlySteps
        ) { success, message in
            DispatchQueue.main.async {
                if success {
                    self.showSuccessAlert(message: "Successfully imported \(totalSteps) steps")
                    
                    NotificationCenter.default.post(
                        name: .refreshStepsData,
                        object: nil,
                        userInfo: ["date": date]
                    )
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
