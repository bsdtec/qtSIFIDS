# qtSIFIDS

Cross-platform Qt 6 / C++ / QML rewrite foundation for SIFIDS.

This is a new project alongside the existing Android app; it does not modify or
replace the original repository. It is an in-progress port, not yet a complete
replacement.

## Build

Install Qt 6.11 or later with the **Qt Location**, **Qt Network**, **Qt
Positioning**, **Qt Quick**, **Qt Quick Controls**, **Qt Quick Dialogs**, and
**Qt SQL (SQLite)** development modules, plus Qt Test, CMake, and a C++17
compiler.

```sh
cmake -S . -B build
cmake --build build
```

Run the `qtSIFIDS` executable from the build output.

### Android

Install the Qt 6.11 Android kit for your target ABI (e.g. `android_arm64_v8a`),
the desktop Qt kit of the same version, Android SDK platform 35 and build-tools,
NDK (the revision recommended by your Qt version) and JDK 17.

```sh
export ANDROID_SDK_ROOT=$HOME/Android/Sdk
export ANDROID_NDK_ROOT=$ANDROID_SDK_ROOT/ndk/<version>
~/Qt/6.11.0/android_arm64_v8a/bin/qt-cmake -S . -B build-android \
    -DQT_HOST_PATH=$HOME/Qt/6.11.0/gcc_64 \
    -DANDROID_SDK_ROOT=$ANDROID_SDK_ROOT -DANDROID_NDK_ROOT=$ANDROID_NDK_ROOT \
    -DSIFIDS_ANDROID_OPENSSL_ROOT=$HOME/Android/android_openssl_16k
cmake --build build-android --target apk
```

The APK is written under `build-android/android-build/build/outputs/apk/`.
Use `--target aab` for a Play Store bundle. Manifest, permissions (internet,
fine/coarse location) and launcher icons are in `android/`; the app requests
location permission at runtime when tracking is first enabled. The package
name is `com.bsdtec.qtSIFIDS`.

**OpenSSL and 16 KB pages:** OSM tiles are served over HTTPS, and Qt on
Android needs OpenSSL 3 libraries bundled (`libssl_3.so`, `libcrypto_3.so`).
The copies shipped with the Android SDK are 4 KB aligned, so Android 15+
shows a "not 16 KB compatible" warning. Clone
[KDAB/android_openssl](https://github.com/KDAB/android_openssl) (the current
`master` is 16 KB aligned) and point `SIFIDS_ANDROID_OPENSSL_ROOT` at it.
Without it the map shows grey tiles on Android.

Install on a device with `adb install -r <apk>`. Debug builds target
arm64-v8a only; a release build needs your own signing keystore.

`cmake --build build-android --target apk` builds the main app and both test
apps, so pick `qtSIFIDS.apk` (package `com.bsdtec.qtSIFIDS`) rather than a
`*_tests.apk`. For a release build, configure a separate directory with
`-DCMAKE_BUILD_TYPE=Release`; Gradle produces an unsigned APK that must be
zip-aligned and signed (e.g. `zipalign` + `apksigner`) before it will install.

### Vessel simulator

Unless you configure with `-DCMAKE_BUILD_TYPE=Release` (or `MinSizeRel`) or
`-DSIFIDS_VESSEL_SIMULATOR=OFF`, an **S** button appears in the map's button
column. It opens a popup with a compass rose (tap/drag) and a speed slider
(0-30 kts), and lets you drop a simulated vessel on the map. The simulation
overrides the GPS position, so tracking, the fishing button, observation and
FISH1 pin drops, pots and sail plan all work against the simulated boat.

## Implemented so far

- QML screens for map/track history, FISH1 forms and rows, observations, and
  vessel/owner settings.
- Local SQLite persistence for forms, form rows, observations, pots, and GPS
  track points.
- Foreground location tracking through Qt Positioning and a Qt Location OSM
  map (pinch/drag/wheel gestures, auto-zoom and re-centre on first fix, follow
  mode) with
  visible attribution. Tracks are drawn as a dotted red line when not fishing
  and a solid orange line when fishing.
- Phone-friendly UI: translucent round map buttons (bottom right) for sail
  plan, fishing, tracking (tap to start/stop, long-press for the tracking
  panel), follow and a + menu; dialogs sized to the usable screen area, and ⋮
  menus on form and row entries. Map gestures are disabled while a dialog is
  open.
- The + menu drops pins at the current position: a FISH1 row, a wildlife
  observation, or a fishing pot (creel icon). Tapping an F or O pin edits that
  row or observation; tapping a pot pin shows its details and lets you delete
  it.
- New FISH1 rows are pre-filled with the current latitude/longitude when a
  GPS fix is available.
- FISH1 CSV export and track CSV export (last 24 hours or all history), saved
  through a file dialog so the files are reachable from the Files app.
- The existing SIFIDS upload endpoint for forms, observations, and locations.
- Backup in Settings: export the whole SQLite database through a file dialog
  (suggested name `qtSIFIDS-db-<yyyymmdd>.sqlite`) and import it again, which
  replaces all data on the device.
- Additive import of forms, rows, observations, and locations from Android
  Room database version 15 (`AppStore::importAndroidDatabase`, covered by
  tests; there is currently no button for it in the UI). Android app
  preferences are not imported.
- A consent confirmation gate for location recording.
- A sail plan (float plan) safety feature, enabled from Settings: record a
  departure point/time and a destination point/time (ETA), share the plan via
  the device's native share sheet (Android's chooser / iOS's
  UIActivityViewController) to any contact in any installed app, then get
  prompted to share your live position, heading, and a map pin at 15, 10 and 5
  minutes before, and at, the ETA so a shore contact knows if you're overdue.
- Tests for database persistence, CRUD, CSV export, Android database import,
  and sail plan check-in scheduling.

The importer supports only version 15 and should be tested against real
anonymized database copies before migration is relied on. It imports
additively, so importing the same file more than once creates duplicates.

## Platform work still required

Qt's positioning API provides a shared interface, but OS permissions and
background execution are platform-specific. Android foreground-service
tracking and notifications (tracking currently runs only while the app is in
the foreground), iOS background location and permissions, and release
signing for Android and iOS are not implemented yet. Linux location
support depends on a provider being installed and available.

The sail plan check-ins only fire while the app is in the foreground, for the
same reason tracking does. The Android share sheet (`src/ShareService.cpp`)
has been built and run; the iOS share sheet (`src/ShareService_ios.mm`) has
only been reviewed, since there is no Xcode/iOS toolchain available to build
or test it here — verify it on a Mac before relying on it.

Pots are stored locally and included in database backups, but are not part of
CSV exports or uploads.

Also not yet ported: the full participant information and consent form, all
original lookup catalog entries and preference categories, scheduled
background uploads, in-app email/share with the CSV attachment, date-based
track filtering beyond last 24 hours/all history, and production validation
against the server.

The upload endpoint currently matches the source app's fixed URL. The consent
screen currently shows a summary for development; it is not a
replacement for the original participant information or a production-ready
consent process. Do not release this build or collect participant data until
the complete approved text and consent workflow have been reviewed and added.

The OSM map plugin is wired for development. Before distribution, choose a
production tile provider, verify its terms and availability on all target
platforms, and confirm any offline-map requirements. The public OSM tile
service is not a general-purpose bulk-download or offline-map service; see
the [tile usage policy](https://operations.osmfoundation.org/policies/tiles/).
