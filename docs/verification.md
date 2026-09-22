# Verification

Verified on 22 September 2026 on an Apple Silicon Mac running macOS 27, using Swift 6.0.3 from Apple's Command Line Tools.

- Release build and ad-hoc app signature verification passed.
- `swift run -c release MandelbrotChecks`: 12 checks, 4,451 assertions, zero failures.
- Inspected the native explorer and export dialog visually.
- Native zoom button changed the horizontal span from 3.4 to 1.7 (2× magnification).
- Saved PNG and JPEG files through the native save dialogs. Independently decoded both files and confirmed 1280 × 800 dimensions and the correct actual image formats.
- Saved a `.mandelbrot` file through the native save dialog and inspected its JSON contents.
- Resized the native window from 1360 × 900 to 1000 × 720 content points.
- Launched the app with the saved file and verified restoration of 2× magnification, 1360 × 900 content size, and 1280 × 800 JPEG export settings.
- Automated control of the Open file picker was unreliable in this environment; restoration was verified through the macOS file-opening launch path, which uses the same loader.

Local release benchmarks (1600 × 1000, four samples per pixel): whole set approximately 0.25 seconds; Seahorse valley approximately 0.87 seconds. These are observations on this machine, not performance guarantees.

Public-release notarization, other macOS versions, Intel hardware, and physical pinch gestures have not been verified here. Automated geometry tests cover the shared zoom math used by pinch and scroll.
