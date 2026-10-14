# Cut Optimiser — Flutter

A responsive, offline-first Flutter prototype for cutting plans on **linear stock** (bars/profiles) and **sheet stock** (boards/panels). The UI uses an industrial navy/slate/orange visual system and adapts from a desktop navigation rail to a compact mobile menu.

## Included

- Dashboard with project and demand summaries.
- Create and select local projects; configure project mode, material, variant/profile, stock format, available stock quantity, unit, kerf, trim and stock cost.
- Add/remove parts and edit demand quantities.
- Linear cutting: best-fit-decreasing heuristic with kerf and trim accounting.
- Sheet cutting: area-sorted bottom-left style rectangle placement with optional 90° rotation, kerf and edge trim.
- Scaled linear and sheet diagrams.
- Local persistence using `shared_preferences` (saved projects survive app restarts on the same device).
- CSV cut-list export and printable/saveable PDF report.
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

## First-run walkthrough

A sample linear job is preloaded. Use **New project** to create a sheet job, configure stock dimensions, add rectangle parts, then choose **Optimisation results** → **Run optimiser**. View the diagram and export the CSV or PDF report. Projects are stored locally on the current device; they are not automatically shared between desktop and mobile.

## Data / algorithm notes

- Dimensions are stored as floating-point values in the selected project unit for prototype speed. A production release should normalise dimensions to integer base units (e.g. micrometres) and validate all conversions.
- Stock quantity `0` means calculate the required quantity. A positive value is treated as available stock and the result warns when the candidate uses more stock than that.
- Cost is captured in project settings but is not yet part of the solver objective.
- The waste percentage is an approximate one-dimensional or usable-sheet-area utilisation estimate. It is not a full manufacturing yield model.

## Multiple stock types per project

A project can now contain multiple stock formats (for example, 50×50 mm and 25×25 mm square tube in one frame project). Add or edit them under **Materials & stock → Manage stock types**, then assign each part to a stock type when adding or editing its demand line. The optimiser groups demand by stock type and solves each group independently, using that stock type’s dimensions, available quantity, kerf, and edge trim. Combined results and exports identify the stock format for each bar or sheet.

Existing projects saved with the previous single `stock` field are migrated to one stock type automatically, and their existing parts are assigned to it.
