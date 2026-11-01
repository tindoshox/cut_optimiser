# Cut Optimiser — Flutter

A responsive, offline-first Flutter prototype for cutting plans on **linear stock** (bars/profiles) and **sheet stock** (boards/panels). The UI uses an industrial navy/slate/orange visual system and adapts from a desktop navigation rail to a compact mobile menu.

## Included

- Dashboard with project and demand summaries.
- Circular-saw branding with matching Android and Windows launcher icons.
- Create and select local projects with named assemblies and production quantities; per-assembly part quantities are multiplied by the number of assemblies to produce.
- Maintain a global material and stock catalog, including dimensions, units, available quantities, kerf, trim, and cost, then reuse those stock types in projects.
- Add/remove assemblies and parts; edit each part's name, dimensions, per-assembly quantity, stock type, and sheet rotation preference.
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

This is a prototype, not a certified production optimiser. The following are **not implemented**: exact solver / optimality proof, robust infeasibility proof, advanced kerf-aware sheet nesting, guillotine cut trees, grain direction, inventory reservations or automatic stock deduction between projects, offcut reuse, supplier pricing logic, machine-specific constraints, cloud synchronisation, team collaboration, automated tests for all geometric edge cases, and release packaging/signing. A project uses one cutting mode (linear or sheet). The sheet placement algorithm is a simple geometric heuristic; independently verify dimensions and every plan before cutting. Parts that fail basic fit checks are called out in the run diagnostics, but the solver does not constitute a formal infeasibility check.

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

## Automated GitHub releases

The GitHub Actions release workflow runs `flutter analyze` and `flutter test`, then builds Windows x64, Linux x64, and Android arm64. Push a version tag matching the version in `pubspec.yaml` (for example, `v0.2.0`) to create a GitHub Release containing:

- `cut_optimiser-windows-x64.zip`
- `cut_optimiser-linux-x64.tar.gz`
- `cut_optimiser-android-arm64-unsigned.apk`

The Android APK is unsigned unless signing is explicitly configured in CI; the workflow does not use or expose signing credentials. A manual workflow dispatch builds and uploads the artifacts for inspection but does not publish a GitHub Release.

## First-run walkthrough

A sample linear job is preloaded. Use **Materials & stock** to create reusable material and stock entries. Create a project, add assemblies with their production quantity, then add each assembly's parts with per-assembly quantities and dimensions. Run the optimiser and export the CSV or PDF report. Global stock quantities are shared by every project, but plans check availability independently and do not reserve or deduct stock. Projects and the catalog are stored locally on the current device; they are not automatically shared between desktop and mobile.

## License

Copyright (C) 2026 Tendai Shoko.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed without any warranty; see the [GNU GPL version 3](https://www.gnu.org/licenses/gpl-3.0.html) for the full license terms.

## Data / algorithm notes

- Dimensions are stored as floating-point values in the selected project unit for prototype speed. A production release should normalise dimensions to integer base units (e.g. micrometres) and validate all conversions.
- Stock quantity `0` means unlimited availability. A positive shared value is checked against each project's plan, but is not reserved or deducted between plans.
- Cost is captured in the global stock catalog but is not yet part of the solver objective.
- The waste percentage is an approximate one-dimensional or usable-sheet-area utilisation estimate. It is not a full manufacturing yield model.

## Global materials and stock

A project can use multiple global stock formats (for example, 50×50 mm and 25×25 mm square tube in one frame project), provided they match that project's cutting mode and unit. Add or edit definitions on the **Materials & stock** page, then assign each part to a stock type. The optimiser groups demand by stock type and solves each group independently, using that stock type's dimensions, shared available quantity, kerf, and edge trim. Combined results and exports identify each stock format.

Existing projects saved with the previous single `stock` field are migrated to a global stock entry automatically. Legacy flat part lists are migrated into a single assembly with a production quantity of one.
