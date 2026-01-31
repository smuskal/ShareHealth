import SwiftUI

struct ImportDetailsView: View {
    let pendingData: PendingImportData
    @Environment(\.dismiss) private var dismiss
    let onAccept: ([String: Any], Bool) -> Void
    
    @State private var isProcessed = false
    @State private var isProcessing = false
    @State private var processedData: [String: Any]?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            // Initial view with process button
            if !isProcessed {
                VStack {
                    Spacer()
                    Button(action: {
                        downloadData()
                    }) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 5)
                            }
                            Text("Process Step Data")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: 250)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isProcessing)
                    
                    Text(pendingData.uuid)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .navigationTitle("Step Import")
                .navigationBarTitleDisplayMode(.inline)
            }
            // Data view after processing
            else if let data = processedData {
                List {
                    Section("Summary") {
                        HStack {
                            Text("Steps")
                            Spacer()
                            Text("\(data["steps"] as? Int ?? 0)")
                                .bold()
                        }
                        
                        HStack {
                            Text("Date")
                            Spacer()
                            Text(data["date"] as? String ?? "")
                                .bold()
                        }
                        
                        HStack {
                            Text("From")
                            Spacer()
                            Text(data["sender"] as? String ?? "")
                                .bold()
                        }
                    }
                    
                    if let notes = data["notes"] as? String, !notes.isEmpty {
                        Section("Notes") {
                            Text(notes)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    if let timeRange = data["time_range"] as? [String: String] {
                        Section("Time Range") {
                            HStack {
                                Text("Start")
                                Spacer()
                                Text(timeRange["start"]?.components(separatedBy: " ")[1] ?? "")
                                    .bold()
                            }
                            
                            HStack {
                                Text("End")
                                Spacer()
                                Text(timeRange["end"]?.components(separatedBy: " ")[1] ?? "")
                                    .bold()
                            }
                        }
                    }
                    
                    if let hourlySteps = data["hourly_steps"] as? [String: Int] {
                        Section("Hourly Breakdown") {
                            ForEach(0...23, id: \.self) { hour in
                                if let steps = hourlySteps["\(hour)"], steps > 0 {
                                    HStack {
                                        Text(formatHour(hour))
                                        Spacer()
                                        Text("\(steps)")
                                            .bold()
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Import Steps")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 16) {
                        Button(action: {
                            onAccept(data, true)
                            dismiss()
                        }) {
                            Text("Add Steps")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .padding(.horizontal)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .padding(.bottom)
                    }
                    .padding(.top, 8)
                    .background(.bar)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            print("\n📱 [IMPORT] ImportDetailsView appeared - ready for user action")
        }
    }
    
    private func downloadData() {
        print("\n🔄 [IMPORT] Starting data download")
        isProcessing = true
        
        var request = URLRequest(url: pendingData.url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    showError(message: "Download failed: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    showError(message: "No data received")
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data)
                    if var jsonDict = json as? [String: Any] {
                        // Add uuid to data
                        jsonDict["_filename"] = pendingData.uuid
                        processedData = jsonDict
                        isProcessed = true
                        print("✅ [IMPORT] Data download complete")
                    } else {
                        showError(message: "Invalid data format")
                    }
                } catch {
                    showError(message: "Failed to parse data")
                }
                isProcessing = false
            }
        }.resume()
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
        isProcessing = false
    }
    
    private func formatHour(_ hour: Int) -> String {
        let isAM = hour < 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(isAM ? "AM" : "PM")"
    }
}
