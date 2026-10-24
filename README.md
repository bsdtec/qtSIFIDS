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
    -DANDROID_SDK_ROOT=$ANDROID_SDK_ROOT -DANDROID_NDK_ROOT=$ANDROID_NDK_ROOT
cmake --build build-android --target apk
```

The APK is written under `build-android/android-build/build/outputs/apk/`.
Use `--target aab` for a Play Store bundle. Manifest and permissions (internet,
fine/coarse location) are in `android/AndroidManifest.xml`; the app requests
location permission at runtime when tracking is first enabled.

## Implemented so far

- QML screens for map/track history, FISH1 forms and rows, observations, and
  vessel/owner settings.
- Local SQLite persistence for forms, form rows, observations, and GPS track
  points.
- Foreground location tracking through Qt Positioning and a Qt Location OSM
  map, including track display and visible attribution.
- FISH1 CSV export and the existing SIFIDS upload endpoint for forms,
  observations, and locations.
- Additive import of forms, rows, observations, and locations from Android
  Room database version 15. Select a database copy from Settings; Android app
  preferences are not imported.
- A consent confirmation gate for location recording.
- Tests for database persistence, CRUD, CSV export, and Android database import.

The importer supports only version 15 and should be tested against real
anonymized database copies before migration is relied on. It imports
additively, so importing the same file more than once creates duplicates.

## Platform work still required

Qt's positioning API provides a shared interface, but OS permissions and
background execution are platform-specific. Android foreground-service
tracking and notifications, iOS background location and permissions, and
packaging/signing for Android and iOS are not implemented yet. Linux location
support depends on a provider being installed and available.

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
