import SwiftUI

/// View for adding custom prediction targets from available health data
struct AddCustomTargetView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FaceToHealthViewModel
    @ObservedObject private var dataStore = FacialDataStore.shared

    @State private var availableMetrics: [String] = []
    @State private var selectedMetric: String?
    @State private var customName: String = ""
    @State private var isLoading = true
    @State private var searchText = ""

    var filteredMetrics: [String] {
        if searchText.isEmpty {
            return availableMetrics
        }
        return availableMetrics.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Scanning health data...")
                        .padding()
                } else if availableMetrics.isEmpty {
                    emptyStateView
                } else {
                    metricsListView
                }
            }
            .navigationTitle("Add Custom Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addTarget()
                    }
                    .disabled(selectedMetric == nil || customName.isEmpty)
                }
            }
            .onAppear {
                scanAvailableMetrics()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Health Data Found")
                .font(.headline)

            Text("Capture faces with health data to see available metrics here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var metricsListView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search metrics...", text: $searchText)
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding()

            // Custom name field
            if let selected = selectedMetric {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected: \(cleanMetricName(selected))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Display Name", text: $customName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

            Divider()

            // Metrics list
            List(filteredMetrics, id: \.self, selection: $selectedMetric) { metric in
                MetricRowView(
                    metric: metric,
                    isSelected: selectedMetric == metric,
                    sampleCount: sampleCount(for: metric)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedMetric = metric
                    if customName.isEmpty {
                        customName = cleanMetricName(metric)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func scanAvailableMetrics() {
        DispatchQueue.global(qos: .userInitiated).async {
            var metricSet = Set<String>()

            // Scan all captures for available health data keys
            for capture in dataStore.captures {
                guard let healthData = capture.healthData else { continue }
                for key in healthData.keys {
                    // Only include numeric values
                    if let value = healthData[key], Double(value) != nil {
                        metricSet.insert(key)
                    }
                }
            }

            // Remove already-used targets
            let builtInIds = Set(PredictionTarget.allTargets.map { $0.id })
            let customIds = Set(viewModel.customTargets.map { $0.id })
            let usedIds = builtInIds.union(customIds)

            // Also map built-in IDs to their health keys
            let builtInHealthKeys: Set<String> = [
                "Heart Rate Variability (ms)",
                "Resting Heart Rate (count/min)"
                // sleepScore is computed, not a direct health key
            ]

            let available = metricSet.subtracting(usedIds).subtracting(builtInHealthKeys)

            DispatchQueue.main.async {
                self.availableMetrics = Array(available).sorted()
                self.isLoading = false
            }
        }
    }

    private func sampleCount(for metric: String) -> Int {
        var count = 0
        for capture in dataStore.captures {
            guard let healthData = capture.healthData,
                  let value = healthData[metric],
                  Double(value) != nil else { continue }
            count += 1
        }
        return count
    }

    private func cleanMetricName(_ metric: String) -> String {
        metric
            .replacingOccurrences(of: " (count)", with: "")
            .replacingOccurrences(of: " (count/min)", with: "")
            .replacingOccurrences(of: " (ms)", with: "")
            .replacingOccurrences(of: " (hr)", with: "")
            .replacingOccurrences(of: " (%)", with: "")
            .replacingOccurrences(of: " (kcal)", with: "")
            .replacingOccurrences(of: " (mi)", with: "")
            .replacingOccurrences(of: " (km)", with: "")
            .replacingOccurrences(of: "[Avg]", with: "Avg")
            .replacingOccurrences(of: "[Min]", with: "Min")
            .replacingOccurrences(of: "[Max]", with: "Max")
            .replacingOccurrences(of: "[Total]", with: "Total")
            .trimmingCharacters(in: .whitespaces)
    }

    private func addTarget() {
        guard let metric = selectedMetric, !customName.isEmpty else { return }
        viewModel.addCustomTarget(name: customName, healthKey: metric)
        dismiss()
    }
}

// MARK: - Metric Row View

private struct MetricRowView: View {
    let metric: String
    let isSelected: Bool
    let sampleCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric)
                    .font(.subheadline)
                    .lineLimit(2)

                Text("\(sampleCount) samples with data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

#Preview {
    AddCustomTargetView(viewModel: FaceToHealthViewModel())
}
