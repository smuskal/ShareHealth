import SwiftUI
import Charts

struct StepsChartView: View {
    let hourlySteps: [String: Int]
    let totalSteps: Int
    let date: Date
    let isDataLoaded: Bool
    let startTime: Date
    let endTime: Date
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    // State for view
    @State private var isDragging = false
    @State private var offset: CGSize = .zero
    @State private var isExpanded = false
    
    // State for data management
    @State private var lastTotalSteps: Int = -1  // Use -1 to force initial update
    @State private var lastDate = Date.distantPast
    @State private var currentViewID = UUID()  // For forcing view updates
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var isFutureDate: Bool {
        let calendar = Calendar.current
        return calendar.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
    }
    
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
                } else if hourlySteps.isEmpty || totalSteps == 0 {
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
                    .id(currentViewID)  // Force view refresh when needed
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                isExpanded = true
            }
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
                            }
                        }
                    }
            )
            .sheet(isPresented: $isExpanded) {
                ZoomedChartView(
                    hourlySteps: hourlySteps,
                    totalSteps: totalSteps,
                    date: date,
                    formattedDate: formattedDate,
                    formattedTimeRange: formattedTimeRange,
                    chartData: chartData,
                    onDismiss: { isExpanded = false }
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .offset(x: isDragging ? offset.width / 3 : 0)
        .onAppear {
            print("\n📊 [CHART] Chart view appeared")
            print("   Date: \(formatDebugDate(date))")
            print("   Total steps: \(totalSteps)")
            checkDataChanges()
        }
        .onChange(of: totalSteps) { oldValue, newValue in
            print("\n🔄 [CHART] Steps changed: \(oldValue) -> \(newValue)")
            checkDataChanges()
        }
        .onChange(of: date) { _, newDate in
            print("\n📅 [CHART] Date changed")
            checkDataChanges()
        }
        .onChange(of: isDataLoaded) { _, _ in
            checkDataChanges()
        }
    }
    
    private func checkDataChanges() {
        let calendar = Calendar.current
        let dateChanged = !calendar.isDate(date, inSameDayAs: lastDate)
        let stepsChanged = totalSteps != lastTotalSteps
        
        if dateChanged || stepsChanged || lastTotalSteps == -1 {
            print("\n🔄 [CHART] Data state update")
            print("   Date changed: \(dateChanged)")
            print("   Steps changed: \(stepsChanged)")
            print("   Current steps: \(totalSteps)")
            print("   Last steps: \(lastTotalSteps)")
            
            // Update tracking state
            lastDate = date
            lastTotalSteps = totalSteps
            
            // Force view refresh
            currentViewID = UUID()
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let isAM = hour < 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour)\(isAM ? "AM" : "PM")"
    }
    
    private func formatDebugDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct ZoomedChartView: View {
    let hourlySteps: [String: Int]
    let totalSteps: Int
    let date: Date
    let formattedDate: String
    let formattedTimeRange: String
    let chartData: [(hour: Int, steps: Int)]
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnificationGesture: CGFloat = 1.0
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    VStack {
                        Text("Steps for \(formattedDate)")
                            .font(.headline)
                            .padding(.top)
                        
                        Text("Time Range: \(formattedTimeRange)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Total Steps: \(totalSteps)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom)
                        
                        if !hourlySteps.isEmpty && totalSteps > 0 {
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
                            .frame(
                                width: max(geometry.size.width * scale, geometry.size.width),
                                height: max(geometry.size.height * 0.6 * scale, geometry.size.height * 0.6)
                            )
                            .gesture(
                                MagnificationGesture()
                                    .updating($magnificationGesture) { value, state, _ in
                                        state = value
                                    }
                                    .onEnded { value in
                                        scale *= value
                                        scale = min(max(1, scale), 3)  // Limit zoom between 1x and 3x
                                    }
                            )
                            .padding()
                        }
                    }
                }
            }
            .navigationBarItems(trailing: Button("Close") {
                onDismiss()
            })
        }
        .presentationDetents([.large])
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
