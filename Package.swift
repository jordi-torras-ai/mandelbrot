// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mandelbrot",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Mandelbrot", targets: ["MandelbrotApp"]),
        .executable(name: "MandelbrotChecks", targets: ["MandelbrotChecks"])
    ],
    targets: [
        .target(name: "FractalEngine", publicHeadersPath: "include"),
        .target(name: "MandelbrotCore", dependencies: ["FractalEngine"]),
        .executableTarget(name: "MandelbrotApp", dependencies: ["MandelbrotCore"]),
        // A standalone test runner also works with Apple's Command Line Tools (without Xcode/XCTest).
        .executableTarget(name: "MandelbrotChecks", dependencies: ["MandelbrotCore", "FractalEngine"], path: "Tests/MandelbrotCoreTests")
    ]
)
