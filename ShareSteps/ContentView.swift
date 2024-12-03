import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var stepManager = StepManager()
    @Binding var importedSteps: Int
    @State private var selectedDate = Date()
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String = ""
    @State private var stepsForRange: Int = 0
    @State private var hourlySteps: [String: Int] = [:]
    @State private var isExporting = false
    @FocusState private var isNotesFocused: Bool
    @State private var isDataLoaded = false
    @State private var lastFetchedDate: Date?
    
    init(importedSteps: Binding<Int>) {
        _importedSteps = importedSteps
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        _startTime = State(initialValue: startOfDay)
        _endTime = State(initialValue: Date())
        print("\n🏗️ [INIT] ContentView initialized")
        print("   Start time: \(startOfDay)")
        print("   End time: \(Date())")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Share Steps")
                    .font(.largeTitle)
                    .padding(.bottom, 10)
                
                DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    .labelsHidden()
                    .onChange(of: selectedDate) { oldValue, newValue in
                        print("\n📅 [DATE_CHANGE] Date selection changed")
                        print("   Old date: \(formatDebugDate(oldValue))")
                        print("   New date: \(formatDebugDate(newValue))")
                        print("   Last fetched: \(lastFetchedDate.map(formatDebugDate) ?? "never")")
                        
                        // Load stored notes for this date
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        let dateString = dateFormatter.string(from: newValue)
                        notes = UserDefaults.standard.getNotes(forDate: dateString) ?? ""
                        
                        updateDateRange(for: newValue, oldDate: oldValue)
                    }

                HStack {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: startTime) { _, _ in
                            print("\n⏰ [TIME] Start time changed to: \(formatDebugTime(startTime))")
                            fetchStepsForTimeRange()
                        }

                    Text("to")

                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: endTime) { _, _ in
                            print("\n⏰ [TIME] End time changed to: \(formatDebugTime(endTime))")
                            fetchStepsForTimeRange()
                        }
                }
                
                VStack(alignment: .leading) {
                    Text("Notes")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    TextEditor(text: $notes)
                        .frame(height: 100)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.3), lineWidth: 2)
                        )
                        .focused($isNotesFocused)
                        .onChange(of: notes) { oldValue, newValue in
                            // Save notes whenever they change
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd"
                            let dateString = dateFormatter.string(from: selectedDate)
                            UserDefaults.standard.saveNotes(newValue, forDate: dateString)
                        }
                }
                .padding(.top, 10)

                StepsChartView(
                    hourlySteps: hourlySteps,
                    totalSteps: stepsForRange,
                    date: selectedDate,
                    isDataLoaded: isDataLoaded,
                    startTime: startTime,
                    endTime: endTime,
                    onSwipeLeft: {
                        handleDateChange(direction: 1)
                    },
                    onSwipeRight: {
                        handleDateChange(direction: -1)
                    }
                )
                .padding(.vertical)

                Button(action: {
                    isNotesFocused = false
                    exportSteps()
                }) {
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Export Steps")
                            .frame(minWidth: 200)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || Calendar.current.compare(selectedDate, to: Date(), toGranularity: .day) == .orderedDescending)
                .padding(.top, 10)

                Spacer()
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture {
            isNotesFocused = false
        }
        .onAppear {
            print("\n🚀 [VIEW] ContentView appearing")
            setupNotificationObservers()
            updateDateRange(for: selectedDate, oldDate: nil)
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .refreshStepsData,
            object: nil,
            queue: .main
        ) { notification in
            if let date = notification.userInfo?["date"] as? Date {
                print("\n🔄 [REFRESH] Refreshing data for \(formatDebugDate(date))")
                self.isDataLoaded = false
                self.hourlySteps = [:]
                self.stepsForRange = 0
                
                self.selectedDate = date
            }
        }
    }
    
    private func handleDateChange(direction: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: direction, to: selectedDate) {
            // Only allow future dates up to today
            if calendar.compare(newDate, to: Date(), toGranularity: .day) != .orderedDescending {
                selectedDate = newDate
            }
        }
    }

    private func updateDateRange(for date: Date, oldDate: Date?) {
        print("\n🔄 [UPDATE_RANGE] Updating date range")
        print("   New date: \(formatDebugDate(date))")
        print("   Old date: \(oldDate.map(formatDebugDate) ?? "none")")
        print("   Current data loaded: \(isDataLoaded)")
        
        let calendar = Calendar.current
        isDataLoaded = false
        hourlySteps = [:]
        stepsForRange = 0
        
        if calendar.compare(date, to: Date(), toGranularity: .day) == .orderedDescending {
            print("⚠️ [UPDATE_RANGE] Future date selected - clearing data")
            isDataLoaded = true
            return
        }
        
        startTime = calendar.startOfDay(for: date)
        if calendar.isDate(date, inSameDayAs: Date()) {
            endTime = Date()
        } else {
            endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date)!
        }
        
        print("📊 [UPDATE_RANGE] Time range set")
        print("   Start: \(formatDebugDateTime(startTime))")
        print("   End: \(formatDebugDateTime(endTime))")
        
        fetchStepsForTimeRange()
    }

    private func fetchStepsForTimeRange() {
        print("\n📥 [FETCH] Starting fetch")
        print("   Date: \(formatDebugDate(selectedDate))")
        print("   Start: \(formatDebugDateTime(startTime))")
        print("   End: \(formatDebugDateTime(endTime))")
        
        stepManager.fetchHourlySteps(start: startTime, end: endTime) { hourlyData in
            DispatchQueue.main.async {
                // Filter data to time range
                let calendar = Calendar.current
                let startHour = calendar.component(.hour, from: startTime)
                let endHour = calendar.component(.hour, from: endTime)
                
                var filteredData: [String: Int] = [:]
                for hour in startHour...endHour {
                    filteredData["\(hour)"] = hourlyData["\(hour)"] ?? 0
                }
                
                self.hourlySteps = filteredData
                self.stepsForRange = filteredData.values.reduce(0, +)
                self.isDataLoaded = true
                self.lastFetchedDate = self.selectedDate
                
                print("\n✅ [FETCH] Data received")
                print("   Hours with data: \(filteredData.count)")
                print("   Total Steps: \(self.stepsForRange)")
                print("   Data loaded state: \(self.isDataLoaded)")
                print("   Last fetched date updated to: \(formatDebugDate(self.selectedDate))")
                
                print("\n📊 [FETCH] Hourly breakdown:")
                let sortedHours = filteredData.sorted { Int($0.key)! < Int($1.key)! }
                sortedHours.forEach { hour, steps in
                    if steps > 0 {
                        print("   Hour \(hour): \(steps) steps")
                    }
                }
            }
        }
    }
    
    private func exportSteps() {
        isExporting = true
        
        let uuid = UUID().uuidString
        let jsonFileName = "\(uuid).json"
        let tempDirectory = FileManager.default.temporaryDirectory

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: selectedDate)
        
        let senderName = UIDevice.current.name
        
        let jsonContent = """
        {
            "steps": \(stepsForRange),
            "date": "\(dateString)",
            "sender": "\(senderName)",
            "notes": "\(notes.replacingOccurrences(of: "\"", with: "\\\""))",
            "time_range": {
                "start": "\(startTime)",
                "end": "\(endTime)"
            },
            "hourly_steps": \(formatHourlySteps(hourlySteps))
        }
        """
        
        let jsonFileURL = tempDirectory.appendingPathComponent(jsonFileName)
        print("📂 [EXPORT] Creating file at: \(jsonFileURL.path)")
        
        do {
            try jsonContent.data(using: String.Encoding.utf8)?.write(to: jsonFileURL)
            print("✅ [EXPORT] JSON file written successfully")
            
            let uploadURL = URL(string: "https://molseek.com/sharedSteps/upload.php")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(uuid, forHTTPHeaderField: "Filename")
            
            print("🌐 [EXPORT] Starting upload to: \(uploadURL.absoluteString)")
            print("🆔 [EXPORT] Using UUID: \(uuid)")
            
            let task = URLSession.shared.uploadTask(with: request, fromFile: jsonFileURL) { data, response, error in
                if error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200 {
                    let appLink = "sharedsteps://\(uuid)"
                    
                    DispatchQueue.main.async {
                        self.isExporting = false
                        
                        // Save notes for this date
                        UserDefaults.standard.saveNotes(self.notes, forDate: dateString)
                        
                        // Present share sheet
                        if let windowScene = UIApplication.shared.connectedScenes
                            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            
                            let messageText = "Here are my \(self.stepsForRange) steps for \(dateString) (\(formatTimeRange(start: self.startTime, end: self.endTime)))!\n\n\(appLink)"
                            
                            let activityVC = UIActivityViewController(
                                activityItems: [messageText],
                                applicationActivities: nil
                            )
                            
                            if let popoverController = activityVC.popoverPresentationController {
                                popoverController.sourceView = rootViewController.view
                                popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                                popoverController.permittedArrowDirections = []
                            }
                            
                            rootViewController.present(activityVC, animated: true)
                        }
                    }
                } else {
                    print("❌ [EXPORT] Upload failed")
                    if let error = error {
                        print("   Error: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self.isExporting = false
                    }
                }
            }
            task.resume()
        } catch {
            print("❌ [EXPORT] Failed to write JSON file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isExporting = false
            }
        }
    }
    
    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private func formatHourlySteps(_ steps: [String: Int]) -> String {
        var allHours: [String] = []
        for hour in 0...23 {
            let stepCount = steps["\(hour)"] ?? 0
            allHours.append("\"\(hour)\": \(stepCount)")
        }
        return "{\n        " + allHours.joined(separator: ",\n        ") + "\n    }"
    }
    
    private func formatDebugDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatDebugTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDebugDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView(importedSteps: .constant(0))
}
