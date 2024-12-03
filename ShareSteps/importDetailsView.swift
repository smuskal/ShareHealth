import SwiftUI

struct ImportDetailsView: View {
    let steps: Int
    let date: String
    let sender: String
    let notes: String?
    let jsonData: [String: Any]
    @Environment(\.dismiss) private var dismiss
    let onAccept: ([String: Any], Bool) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    HStack {
                        Text("Steps")
                        Spacer()
                        Text("\(steps)")
                            .bold()
                    }
                    
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(date)
                            .bold()
                    }
                    
                    HStack {
                        Text("From")
                        Spacer()
                        Text(sender)
                            .bold()
                    }
                }
                
                if let notes = notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                if let timeRange = jsonData["time_range"] as? [String: String] {
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
                
                if let hourlySteps = jsonData["hourly_steps"] as? [String: Int] {
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
                        print("\n🔄 [IMPORT] User accepted step import")
                        print("   Date: \(date)")
                        print("   Total steps: \(steps)")
                        print("   From: \(sender)")
                        onAccept(jsonData, true)
                        dismiss()
                    }) {
                        Text("Add Steps")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal)
                    
                    Button("Cancel") {
                        print("\n❌ [IMPORT] User cancelled step import")
                        dismiss()
                    }
                    .padding(.bottom)
                }
                .padding(.top, 8)
                .background(.bar)
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let isAM = hour < 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(isAM ? "AM" : "PM")"
    }
}
