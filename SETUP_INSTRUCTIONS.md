# ShareHealth - Developer Setup Instructions

Detailed instructions for building and deploying ShareHealth to your iPhone.

## Prerequisites

- macOS with Xcode 16+ installed
- Apple Developer account (free or paid)
- iPhone with iOS 18+
- USB cable to connect iPhone to Mac

## Step 1: Open the Project

1. Clone or download the repository
2. Double-click `ShareHealth.xcodeproj` to open in Xcode
3. Wait for Xcode to index the project

## Step 2: Configure Signing

1. In Xcode, click on **ShareHealth** in the project navigator
2. Select the **ShareHealth** target
3. Go to **Signing & Capabilities** tab
4. Under **Signing**:
   - Check "Automatically manage signing"
   - Select your Team (Apple Developer account)
5. Verify these capabilities are enabled:
   - HealthKit
   - (Camera access is handled via Info.plist)

## Step 3: Connect Your iPhone

1. Connect iPhone to Mac via USB
2. Trust the computer if prompted on iPhone
3. In Xcode, select your iPhone from the device dropdown
   - Should show your device name, not "Any iOS Device"

## Step 4: Enable Developer Mode (iOS 16+)

If not already enabled:

1. On iPhone: **Settings > Privacy & Security > Developer Mode**
2. Enable Developer Mode
3. iPhone will restart
4. Confirm when prompted after restart

## Step 5: Build and Run

1. Click the **Play button** (▶) or press **Cmd+R**
2. Wait for build to complete
3. App will install and launch on iPhone

## Step 6: Grant Permissions

On first launch:

1. **HealthKit**: Tap "Turn On All" to grant access to health categories
2. **Camera** (if using face imagery): Allow when prompted

## Troubleshooting

### Signing Errors
- Add your Apple ID in **Xcode > Settings > Accounts**
- Try a unique Bundle Identifier (e.g., `com.yourname.ShareHealth`)
- Ensure "Automatically manage signing" is checked

### "Untrusted Developer" on iPhone
1. **Settings > General > VPN & Device Management**
2. Find your Developer certificate
3. Tap **Trust**

### HealthKit Errors
- Verify HealthKit capability is added
- Delete app and reinstall
- Check Health app permissions

### Build Errors
- **Product > Clean Build Folder** (Cmd+Shift+K)
- Rebuild with Cmd+R

## File Locations

After export, files are saved to your chosen location:
- **CSV**: `HealthMetrics-YYYY-MM-DD.csv`
- **Face images**: `Faces/Face-YYYY-MM-DD_HHMMSS.jpg`

## Cloud Storage Setup

### Dropbox
1. Install Dropbox app on iPhone
2. Enable "Allow Dropbox to access files" in Dropbox settings
3. Dropbox appears under "Locations" in Files app

### iCloud Drive
- Works automatically if signed into iCloud

### Google Drive
1. Install Google Drive app
2. Enable Files integration in Drive settings

## Daily Usage

1. Open ShareHealth
2. Tap **Export Health Data**
3. Select date
4. Tap **Export to Default Folder**
5. Take selfie if face imagery is enabled
6. Done!

## Technical Notes

- Exports ~100 health data types from HealthKit
- Data aggregation: sums for activity, averages for vitals
- Sleep data prioritizes dedicated sleep trackers (Eight Sleep, Oura)
- Face images: JPEG at 85% quality
- Security-scoped bookmarks maintain folder access between sessions
