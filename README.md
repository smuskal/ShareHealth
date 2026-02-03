# ShareHealth

[![Available on the App Store](https://img.shields.io/badge/App%20Store-Available-blue?logo=apple)](https://apps.apple.com/us/app/sharehealth/id6738940089)

An iOS app for exporting Apple Health data to CSV files with optional face imagery tracking.

**[Download on the App Store](https://apps.apple.com/us/app/sharehealth/id6738940089)**

## Features

### Health Data Export
Export 100+ Apple Health metrics to CSV format, including:
- **Activity**: Steps, flights climbed, exercise time, distances
- **Heart**: Heart rate (min/max/avg), resting HR, HRV, walking HR
- **Sleep**: Total, asleep, **time in bed**, core, deep, REM, awake durations, **bedtime** (decimal hours), **wake time** (decimal hours)
- **Vitals**: Blood pressure, body temperature, blood glucose, respiratory rate
- **Body**: Weight, height, BMI, body fat percentage, lean mass
- **Nutrition**: Calories, macros, vitamins, minerals (20+ nutrients)
- **Mobility**: Walking speed, step length, stair speed, 6-minute walk test
- **Other**: Mindful minutes, handwashing, stand hours, and more

### Sleep Timing for Analytics
Bedtime and Wake Time are exported as **decimal hours** (24-hour format) for easy use in machine learning models and data analysis:
- **Bedtime**: Earliest sleep session start time (e.g., 22.75 = 10:45 PM)
- **Wake Time**: Latest asleep sample end time before 6 PM (e.g., 6.5 = 6:30 AM)
- **Time in Bed**: Total hours spent in bed (separate from asleep time)

This format is designed for predictive analytics and health trend modeling.

### Historical Export (Date Range)
Export health data for any date range with a single batch operation:
- Select custom start and end dates
- **Automatic earliest date detection** - displays your earliest available HealthKit data with a "Use" button
- Exports one CSV file per day containing all 100+ health metrics
- Real-time progress tracking showing current day being exported
- **View Log** feature to review export details, timing, and any failed days
- **Screen stays awake** during export to prevent interruption on long exports
- **30-second timeout per day** to gracefully handle stuck HealthKit queries
- Continues to next day on failure (doesn't abort entire export)
- Separate folder selection from single-day exports for organization

### Organized Folder Structure
All exports are organized into year/month subfolders:
```
/ExportFolder/
  /2024/
    /01/
      HealthMetrics-2024-01-01.csv
      HealthMetrics-2024-01-02.csv
      ...
    /02/
      HealthMetrics-2024-02-01.csv
      ...
  /faces/
    /2024/
      /01/
        Face-2024-01-15_143022.jpg
        ...
```

### Face Imagery
Optionally capture a selfie with each health export to track your appearance alongside your health metrics:
- Front-facing camera with preview
- Retake option before saving
- Photos saved to `faces/YYYY/MM/` subfolder structure
- Persists preference across sessions

### Flexible Export Locations
- **Default Folder**: Set once, export with one tap
- **Dedicated Historical Export Folder**: Separate folder for batch exports
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

### Single Day Export

1. Open the app and tap **Export Health Data**
2. Select the date you want to export
3. Tap **Export to Default Folder** or **Export to Other Location**
4. If face imagery is enabled, take a selfie when prompted
5. Your CSV file will be saved to `YYYY/MM/HealthMetrics-YYYY-MM-DD.csv`

### Historical Export (Date Range)

1. Open the app and tap **Historical Export**
2. The app displays your **earliest available health data date**
3. Select start date (tap "Use" to start from earliest available)
4. Select end date
5. Choose an export folder
6. Tap **Export X Days**
7. Monitor progress - shows current day being exported
8. When complete, tap **View Log** to see details and any failures

### CSV Format

The exported CSV includes a header row with metric names and units, followed by a single data row with values for the selected date. Format is compatible with spreadsheet applications and data analysis tools.

Example columns:
```
Date/Time, Active Energy (kcal), Step Count (count), Heart Rate [Avg] (count/min), Sleep Analysis [Total] (hr), Bedtime, Wake Time, ...
```

**Sleep Data Fields:**
- `Sleep Analysis [In Bed] (hr)`: Hours spent in bed (may differ from asleep time)
- `Bedtime`: Decimal hour when sleep session started (24-hour format)
- `Wake Time`: Decimal hour when final sleep ended (morning wake-up)
- Example values: `22.75` = 10:45 PM, `6.5` = 6:30 AM
- Optimized for machine learning, predictive analytics, and sleep pattern analysis

## Project Structure

```
ShareHealth/
├── ShareStepsApp.swift          # App entry point
├── MainMenuView.swift           # Main navigation (3 options)
├── HealthExportView.swift       # Single-day export UI
├── HistoricalExportView.swift   # Date range export UI
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

- **3.0 (Build 3)** - Historical export with date range selection, bedtime/wake time fields as decimal hours for ML/analytics, time in bed tracking, year/month folder organization, export logging with View Log feature, automatic earliest available date detection, 30-second per-day timeout protection, screen stays awake during batch exports
- **3.0 (Build 2)** - Initial 3.0 release with historical export foundation
- **2.1** - Added face imagery capture, health export improvements
- **2.0** - Added comprehensive health data export (70+ metrics)
- **1.x** - Original ShareSteps functionality

## Troubleshooting

### Historical Export Issues

**Export seems to stop mid-way:**
- Keep the app in foreground during export
- The screen stays awake automatically
- Check the View Log for failed days
- Each day has a 30-second timeout to prevent hanging

**Files not appearing in Dropbox:**
- Files are written to local Dropbox cache first
- Dropbox uploads them to cloud in the background
- Check Files app → Dropbox to see local files
- Keep Dropbox app open to speed up uploads

**No sleep data for older years:**
- Native Apple sleep tracking started in September 2020 (iOS 14)
- Earlier sleep data requires third-party apps (Sleep Cycle, AutoSleep, etc.)
- CSVs will still export with other metrics; sleep fields will be empty

## License

Private repository. All rights reserved.

## Acknowledgments

Built with SwiftUI, HealthKit, and AVFoundation.
