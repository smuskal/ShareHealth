# ShareHealth

An iOS app for exporting Apple Health data to CSV files with optional face imagery tracking.

## Features

### Health Data Export
Export 70+ Apple Health metrics to CSV format, including:
- **Activity**: Steps, flights climbed, exercise time, distances
- **Heart**: Heart rate (min/max/avg), resting HR, HRV, walking HR
- **Sleep**: Total, asleep, in bed, core, deep, REM, awake durations
- **Vitals**: Blood pressure, body temperature, blood glucose, respiratory rate
- **Body**: Weight, height, BMI, body fat percentage, lean mass
- **Nutrition**: Calories, macros, vitamins, minerals (20+ nutrients)
- **Mobility**: Walking speed, step length, stair speed, 6-minute walk test
- **Other**: Mindful minutes, handwashing, stand hours, and more

### Face Imagery
Optionally capture a selfie with each health export to track your appearance alongside your health metrics:
- Front-facing camera with preview
- Retake option before saving
- Photos saved to a `Faces/` subfolder
- Persists preference across sessions

### Flexible Export Locations
- **Default Folder**: Set once, export with one tap
- **Share Sheet**: Export to any app (email, cloud storage, etc.)
- Works with iCloud Drive, Dropbox, Google Drive, or local storage

### Share Steps
Share your daily step counts with friends via URL scheme.

## Requirements

- iOS 18.0+
- iPhone with HealthKit support
- Xcode 16+ (for building)
- Apple Developer account

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/smuskal/ExportHealth.git
   cd ExportHealth
   ```

2. Open in Xcode:
   ```bash
   open ShareHealth.xcodeproj
   ```

3. Configure signing:
   - Select the `ShareHealth` target
   - Go to **Signing & Capabilities**
   - Select your development team
   - Xcode will automatically manage provisioning

4. Build and run:
   - Connect your iPhone
   - Select your device from the scheme dropdown
   - Press `Cmd+R` or click the Play button

### First Launch

1. Grant HealthKit permissions when prompted
2. Set a default export folder (optional but recommended)
3. Enable "Include Face Imagery" if desired

## Usage

### Export Health Data

1. Open the app and tap **Export Health Data**
2. Select the date you want to export
3. Tap **Export to Default Folder** or **Export to Other Location**
4. If face imagery is enabled, take a selfie when prompted
5. Your CSV file will be saved as `HealthMetrics-YYYY-MM-DD.csv`

### CSV Format

The exported CSV includes a header row with metric names and units, followed by a single data row with values for the selected date. Format is compatible with spreadsheet applications and data analysis tools.

Example columns:
```
Date/Time, Active Energy (kcal), Step Count (count), Heart Rate [Avg] (count/min), Sleep Analysis [Total] (hr), ...
```

## Project Structure

```
ShareHealth/
├── ShareStepsApp.swift          # App entry point
├── MainMenuView.swift           # Main navigation
├── HealthExportView.swift       # Export UI and logic
├── HealthDataExporter.swift     # HealthKit data fetching
├── FaceCaptureView.swift        # Camera capture UI
├── ContentView.swift            # Share Steps feature
├── StepsChartView.swift         # Step visualization
└── ...
```

## Privacy

This app:
- Reads health data locally from Apple HealthKit
- Does not transmit health data to any external servers
- Stores exports only where you choose to save them
- Camera is only used when face imagery feature is enabled
- All data stays on your device or your chosen cloud storage

## Permissions Required

| Permission | Purpose |
|------------|---------|
| HealthKit (Read) | Access health metrics for export |
| HealthKit (Write) | Save imported step data from friends |
| Camera | Capture face photos (optional) |
| File Access | Save exports to selected folder |

## Building for Release

1. In Xcode, select **Product > Archive**
2. In the Organizer, click **Distribute App**
3. Choose **App Store Connect** for TestFlight/App Store
4. Or choose **Ad Hoc** for direct installation

## Version History

- **2.1** - Added face imagery capture, health export improvements
- **2.0** - Added comprehensive health data export (70+ metrics)
- **1.x** - Original ShareSteps functionality

## License

Private repository. All rights reserved.

## Acknowledgments

Built with SwiftUI, HealthKit, and AVFoundation.
