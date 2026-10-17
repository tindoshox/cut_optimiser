# Cut Optimiser — Flutter

A responsive, offline-first Flutter prototype for cutting plans on **linear stock** (bars/profiles) and **sheet stock** (boards/panels). The UI uses an industrial navy/slate/orange visual system and adapts from a desktop navigation rail to a compact mobile menu.

## Included

- Dashboard with project and demand summaries.
- Circular-saw branding with matching Android and Windows launcher icons.
- Create and select local projects; configure project mode, material, variant/profile, stock format, available stock quantity, unit, kerf, trim and stock cost.
- Add/remove parts and edit demand quantities.
- Linear cutting: compares best-fit and first-fit packing across descending, ascending and entered part orders, with kerf and trim accounting.
- Sheet cutting: compares area, longest-side, width, height and perimeter part orders, then keeps the layout with the fewest sheets and best compactness; supports optional 90° rotation, kerf and edge trim.
- Scaled linear and sheet diagrams.
- Mark individual placed parts as cut directly on the diagrams or from their part chips; cut status is saved with the project.
- Cutting diagrams label the remaining bar offcut length and the unused sheet area.
- Identical bar and sheet layouts are grouped into a single diagram; individual part chips remain available for cut tracking.
- Local persistence using `shared_preferences` (saved projects survive app restarts on the same device).
- CSV cut-list export and printable/saveable PDF report.
- About page with application details, prototype limitations, and copyright/license information.
- Explicit status text stating that the heuristic candidate is **not proven globally optimal**.

## Important scope boundaries

This is a prototype, not a certified production optimiser. The following are **not implemented**: exact solver / optimality proof, robust infeasibility proof, advanced kerf-aware sheet nesting, guillotine cut trees, grain direction, material compatibility rules, inventory transactions/offcut reuse, multi-stock optimisation, supplier pricing logic, machine-specific constraints, cloud synchronisation, team collaboration, automated tests for all geometric edge cases, and release packaging/signing. The sheet placement algorithm is a simple geometric heuristic; independently verify dimensions and every plan before cutting. Parts that fail basic fit checks are called out in the run diagnostics, but the solver does not constitute a formal infeasibility check.

## Run it

Requires a current Flutter stable SDK and the platform toolchains for the target OS.

1. Unzip the project.
2. From this directory, run `flutter create --platforms=linux,windows,android .` if platform runner folders are not present.
3. Run `flutter pub get`.
4. Run on desktop: `flutter run -d linux` or `flutter run -d windows`.
5. Run on Android: `flutter run -d <android-device-id>`.
6. Build with `flutter build linux`, `flutter build windows`, or `flutter build apk`.

The archive includes app source and dependency configuration, not compiled platform binaries. Linux requires the Flutter Linux desktop prerequisites; Windows builds require Visual Studio with the C++ desktop workload; Android requires Android SDK/toolchain setup.

## Android arm64 release build

Build an arm64 APK on a Linux, macOS, or Windows host with Flutter stable and the Android SDK configured:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The arm64 APK is written to `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Without signing configuration it is unsigned and must be signed before installation or distribution. To sign release builds, create and securely back up an upload keystore, then add the following ignored local file at `android/key.properties` (keep all passwords and keystore files out of version control):

```properties
storePassword=<keystore-password>
keyPassword=<key-password>
keyAlias=upload
storeFile=upload-keystore.jks
```

Place the keystore at `android/app/upload-keystore.jks`, or set `storeFile` to its path relative to `android/app`. Re-run the release build; Gradle signs it with that key. Do not lose the keystore or passwords: updates to an installed app must be signed with the same key. Before publishing, set a unique permanent Android application ID in `android/app/build.gradle.kts` and choose the release version/build number in `pubspec.yaml`.

## Linux release build

Build Linux releases on a Linux host with Flutter stable and the GTK 3 desktop development dependencies installed. On Ubuntu or Debian, install the prerequisites with:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev
```

Then build and verify the release:

```sh
flutter pub get
flutter analyze
flutter test
flutter build linux --release
```

Distribute the complete `build/linux/x64/release/bundle` directory (or zip its contents); the executable depends on the accompanying `data` and `lib` directories. The bundle is unsigned and does not include an installer or desktop integration. It requires a compatible Linux system with GTK 3 libraries. Before publishing, choose the product version in `pubspec.yaml` and arrange package creation/signing if required by the distribution channel.

## Windows release build

Build Windows releases on a Windows host with Flutter stable and Visual Studio installed with the **Desktop development with C++** workload:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Distribute the complete `build\windows\x64\runner\Release` directory (or zip its contents); the executable depends on the accompanying Flutter runtime, `data` directory, and plugin libraries. The build is unsigned and does not include an installer. Before publishing, choose the product version in `pubspec.yaml` and arrange code signing or installer packaging if required by the distribution channel.

## First-run walkthrough

A sample linear job is preloaded. Use **New project** to create a sheet job, configure stock dimensions, add rectangle parts, then choose **Optimisation results** → **Run optimiser**. View the diagram and export the CSV or PDF report. Open **About** from the navigation menu for app information, limitations, and license details. Projects are stored locally on the current device; they are not automatically shared between desktop and mobile.

## License

Copyright (C) 2026 Tendai Shoko.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed without any warranty; see the [GNU GPL version 3](https://www.gnu.org/licenses/gpl-3.0.html) for the full license terms.

## Data / algorithm notes

- Dimensions are stored as floating-point values in the selected project unit for prototype speed. A production release should normalise dimensions to integer base units (e.g. micrometres) and validate all conversions.
- Stock quantity `0` means calculate the required quantity. A positive value is treated as available stock and the result warns when the candidate uses more stock than that.
- Cost is captured in project settings but is not yet part of the solver objective.
- The waste percentage is an approximate one-dimensional or usable-sheet-area utilisation estimate. It is not a full manufacturing yield model.

## Multiple stock types per project

A project can now contain multiple stock formats (for example, 50×50 mm and 25×25 mm square tube in one frame project). Add or edit them under **Materials & stock → Manage stock types**, then assign each part to a stock type when adding or editing its demand line. The optimiser groups demand by stock type and solves each group independently, using that stock type’s dimensions, available quantity, kerf, and edge trim. Combined results and exports identify the stock format for each bar or sheet.

Existing projects saved with the previous single `stock` field are migrated to one stock type automatically, and their existing parts are assigned to it.
