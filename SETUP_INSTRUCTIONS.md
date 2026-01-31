# ShareSteps with Health Export - Setup Instructions

This document explains how to build and deploy the ShareSteps app with the new Health Export functionality to your iPhone.

## New Features Added

1. **Main Menu Screen** - When you open the app, you'll see two options:
   - **Export Health Data** - Export all Apple Health metrics to CSV
   - **Share Steps** - The existing step sharing functionality

2. **Health Export** - Exports comprehensive health data including:
   - Activity & Steps
   - Heart Rate & Vitals
   - Sleep Analysis
   - Nutrition Data
   - Respiratory Metrics
   - Body Measurements
   - And 100+ other health metrics

3. **CSV Format** - Exports match your existing format: `HealthMetrics-YYYY-MM-DD.csv`

4. **Dropbox Integration** - Uses iOS Files app integration, so you can save directly to your Dropbox folder without any API setup.

## Files Modified/Added

### New Files:
- `MainMenuView.swift` - Main menu with two options
- `HealthDataExporter.swift` - Core export logic for all health data types
- `HealthExportView.swift` - UI for the health export feature

### Modified Files:
- `ShareStepsApp.swift` - Changed root view to MainMenuView
- `WelcomeView.swift` - Updated descriptions
- `Info.plist` - Added comprehensive HealthKit descriptions
- `ShareSteps.entitlements` - Added read-write file access

---

## Step-by-Step Setup Instructions

### Prerequisites
- macOS with Xcode 15+ installed
- Apple Developer account (free or paid)
- iPhone with iOS 16+ (for Charts framework)
- USB cable to connect iPhone to Mac

### Step 1: Open the Project in Xcode

1. Navigate to the project folder:
   ```
   /Users/smuskal/eidogen-sertanty Dropbox/Steven Muskal/SharedSteps-archive/V3/
   ```

2. Double-click `ShareSteps.xcodeproj` to open in Xcode

3. Wait for Xcode to index the project (may take a minute)

### Step 2: Configure Signing & Capabilities

1. In Xcode, click on **ShareSteps** in the project navigator (left sidebar)
2. Select the **ShareSteps** target
3. Go to the **Signing & Capabilities** tab
4. Under **Signing**:
   - Check "Automatically manage signing"
   - Select your Team (your Apple Developer account)
   - If you see an error, click "Register Device" or "Try Again"

5. Verify HealthKit capability is enabled:
   - You should see "HealthKit" in the capabilities list
   - If not, click "+ Capability" and add "HealthKit"

### Step 3: Connect Your iPhone

1. Connect your iPhone to your Mac via USB cable
2. On your iPhone, trust the computer if prompted
3. In Xcode, select your iPhone from the device dropdown (top of window)
   - It should say something like "Steven's iPhone"
   - NOT "Any iOS Device (arm64)"

### Step 4: Enable Developer Mode on iPhone (iOS 16+)

If you haven't done this before:

1. On your iPhone, go to **Settings > Privacy & Security**
2. Scroll down and tap **Developer Mode**
3. Enable Developer Mode
4. Your iPhone will restart
5. After restart, confirm enabling Developer Mode when prompted

### Step 5: Build and Run

1. In Xcode, click the **Play button** (▶) or press **Cmd+R**
2. Wait for the build to complete (first build may take longer)
3. The app will install and launch on your iPhone

### Step 6: Grant Health Permissions

When the app first launches:

1. Tap **"Enable HealthKit Access"**
2. You'll see the Health access screen
3. Tap **"Turn On All"** to grant access to all health categories
4. Tap **"Allow"** to confirm

### Step 7: Using Health Export

1. From the main menu, tap **"Export Health Data"**
2. If needed, tap **"Grant Health Access"** for additional permissions
3. Select the date you want to export
4. Tap **"Export to CSV"**
5. The iOS file picker will appear
6. Navigate to your Dropbox folder:
   ```
   Dropbox > Apps > Health Auto Export > Health Auto Export > AppleHealth
   ```
7. Tap **"Save"**

The file will be named `HealthMetrics-YYYY-MM-DD.csv` automatically.

---

## Troubleshooting

### "Unable to install" or signing errors
- Make sure your Apple ID is added in Xcode > Settings > Accounts
- Try changing the Bundle Identifier to something unique (e.g., `com.yourname.ShareSteps`)
- Ensure "Automatically manage signing" is checked

### "Untrusted Developer" error on iPhone
1. On iPhone, go to **Settings > General > VPN & Device Management**
2. Find your Developer App certificate
3. Tap **"Trust"**

### App crashes or HealthKit errors
- Make sure HealthKit capability is added in Signing & Capabilities
- Delete the app from iPhone and reinstall

### Can't find Dropbox in file picker
- Make sure Dropbox app is installed on your iPhone
- In Dropbox app settings, enable "Allow Dropbox to access files"
- The Dropbox folder should appear under "Locations" in Files

### Build errors about missing files
- In Xcode, try **Product > Clean Build Folder** (Cmd+Shift+K)
- Then build again (Cmd+R)

---

## Daily Usage

To export health data daily:

1. Open the ShareSteps app on your iPhone
2. Tap "Export Health Data"
3. Select today's date (or any date)
4. Tap "Export to CSV"
5. Save to your Dropbox folder

The file will overwrite any existing file with the same name, so you can run exports multiple times per day.

---

## Optional: Create Home Screen Shortcut

You can create a shortcut for quick access:

1. Open the **Shortcuts** app on iPhone
2. Tap **+** to create new shortcut
3. Add action "Open App"
4. Select "ShareSteps"
5. Name it "Export Health"
6. Tap the share icon and "Add to Home Screen"

This gives you a one-tap icon to open the app.

---

## Technical Notes

- The export reads ~120 health data types from HealthKit
- Data is aggregated for the selected day (sums for activity, averages for vitals, etc.)
- CSV format matches your existing Health Auto Export format
- Uses iOS's native document picker for file saving (works with any cloud storage)
