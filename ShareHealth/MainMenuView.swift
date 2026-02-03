import SwiftUI

struct MainMenuView: View {
    @Binding var importedSteps: Int
    let shouldFetchHealthData: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("ShareHealth")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)

                Text("Health Data Tools")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                VStack(spacing: 20) {
                    NavigationLink(destination: HealthExportView()) {
                        MenuButton(
                            title: "Export Health Data",
                            subtitle: "Export all Apple Health metrics to CSV",
                            iconName: "square.and.arrow.up",
                            color: .green
                        )
                    }

                    NavigationLink(destination: HistoricalExportView()) {
                        MenuButton(
                            title: "Historical Export",
                            subtitle: "Export data for a date range",
                            iconName: "calendar.badge.clock",
                            color: .orange
                        )
                    }

                    NavigationLink(destination: ContentView(importedSteps: $importedSteps, shouldFetchHealthData: shouldFetchHealthData)) {
                        MenuButton(
                            title: "Share Steps",
                            subtitle: "Share step counts with friends",
                            iconName: "figure.walk",
                            color: .blue
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}

struct MenuButton: View {
    let title: String
    let subtitle: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 30))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(color)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

#Preview {
    MainMenuView(importedSteps: .constant(0), shouldFetchHealthData: true)
}
