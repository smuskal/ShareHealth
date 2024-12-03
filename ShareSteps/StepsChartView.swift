import SwiftUI
import Charts

struct StepsChartView: View {
    let hourlySteps: [String: Int]
    let totalSteps: Int
    let date: Date
    let isDataLoaded: Bool
    let startTime: Date  // Added
    let endTime: Date    // Added
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var isFutureDate: Bool {
        let calendar = Calendar.current
        return calendar.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
    }
    
    // Modified to respect time range
    var chartData: [(hour: Int, steps: Int)] {
        if isFutureDate {
            return []
        }
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: startTime)
        let endHour = calendar.component(.hour, from: endTime)
        
        return (0..<24).compactMap { hour in
            if hour >= startHour && hour <= endHour {
                return (hour: hour, steps: hourlySteps["\(hour)"] ?? 0)
            }
            return nil
        }
    }
    
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps for \(formattedDate)")
                .font(.headline)
            
            Text("Time Range: \(formattedTimeRange)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Total Steps: \(totalSteps)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ZStack {
                if isFutureDate {
                    Text("No data available for future dates")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if !isDataLoaded {
                    ProgressView("Loading steps data...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack {
                        if hourlySteps.isEmpty || totalSteps == 0 {
                            Text("No steps recorded")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Chart {
                                ForEach(chartData, id: \.hour) { data in
                                    if data.steps > 0 {
                                        BarMark(
                                            x: .value("Hour", formatHour(data.hour)),
                                            y: .value("Steps", data.steps)
                                        )
                                        .foregroundStyle(Color.blue)
                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        isDragging = true
                        offset = gesture.translation
                    }
                    .onEnded { gesture in
                        isDragging = false
                        offset = .zero
                        
                        let threshold: CGFloat = 50
                        if gesture.translation.width > threshold {
                            print("\n👈 [SWIPE] Previous day")
                            onSwipeRight()
                        } else if gesture.translation.width < -threshold {
                            if !isFutureDate {
                                print("\n👉 [SWIPE] Next day")
                                onSwipeLeft()
                            } else {
                                print("\n⚠️ [SWIPE] Prevented swipe to future date")
                            }
                        }
                    }
            )
            .animation(.easeOut, value: offset)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .offset(x: isDragging ? offset.width / 3 : 0)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let isAM = hour < 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour)\(isAM ? "AM" : "PM")"
    }
}

#Preview {
    StepsChartView(
        hourlySteps: ["9": 1000, "10": 2000, "11": 1500],
        totalSteps: 4500,
        date: Date(),
        isDataLoaded: true,
        startTime: Calendar.current.startOfDay(for: Date()),
        endTime: Date(),
        onSwipeLeft: {},
        onSwipeRight: {}
    )
    .padding()
}
