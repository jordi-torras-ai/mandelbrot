import Foundation

public enum Palette: String, Codable, CaseIterable {
    case midnight, electric, arctic
    public var title: String { rawValue.capitalized }
    public var index: Int32 { Int32(Self.allCases.firstIndex(of: self)!) }
}

public struct ViewState: Codable, Equatable {
    public var centerX: Double = -0.6
    public var centerY: Double = 0
    /// Horizontal extent of the complex plane. Vertical extent follows the image aspect ratio.
    public var span: Double = 3.4
    public var iterations: Int = 800
    public var colorPeriod: Double = 120
    public var palette: Palette = .midnight
    public static let minimumSpan = 1e-11
    public static let maximumSpan = 12.0
    public init() {}
    public var zoom: Double { 3.4 / span }

    public func validated() throws -> Self {
        guard centerX.isFinite, centerY.isFinite, abs(centerX) <= 10, abs(centerY) <= 10,
              span.isFinite, (Self.minimumSpan...Self.maximumSpan).contains(span),
              (100...20000).contains(iterations), colorPeriod.isFinite, (20...500).contains(colorPeriod) else {
            throw MandelbrotError.invalidView
        }
        return self
    }

    /// Anchor coordinates are fractions measured from the top left of the viewport.
    public mutating func zoom(by factor: Double, anchorX: Double = 0.5, anchorY: Double = 0.5, aspect: Double = 1) {
        guard factor.isFinite, factor > 0, aspect.isFinite, aspect > 0 else { return }
        let nextSpan = min(Self.maximumSpan, max(Self.minimumSpan, span / factor))
        centerX += (anchorX - 0.5) * (span - nextSpan)
        centerY += (0.5 - anchorY) * (span - nextSpan) / aspect
        centerX = min(10, max(-10, centerX))
        centerY = min(10, max(-10, centerY))
        span = nextSpan
    }

    public mutating func pan(fractionX: Double, fractionY: Double, aspect: Double) {
        guard aspect > 0, aspect.isFinite, fractionX.isFinite, fractionY.isFinite else { return }
        centerX = min(10, max(-10, centerX - fractionX * span))
        centerY = min(10, max(-10, centerY + fractionY * span / aspect))
    }
}

public struct Destination {
    public let name: String
    public let detail: String
    public let view: ViewState
    public static let all: [Destination] = {
        func place(_ name: String, _ detail: String, _ x: Double, _ y: Double, _ span: Double, _ iterations: Int) -> Destination {
            var view = ViewState()
            view.centerX = x; view.centerY = y; view.span = span; view.iterations = iterations
            return Destination(name: name, detail: detail, view: view)
        }
        return [
            place("The whole set", "A familiar beginning", -0.6, 0, 3.4, 800),
            place("Seahorse valley", "Spirals on the shoreline", -0.748, 0.102, 0.018, 1600),
            place("Elephant valley", "Where the edges fold", 0.275, 0.008, 0.018, 1600),
            place("Satellite", "A world within a world", -1.768, 0.001, 0.025, 1600),
            place("The deep spiral", "A little further in", -0.743643887037151, 0.131825904205330, 0.000018, 3200)
        ]
    }()
}

public enum ImageFormat: String, Codable, CaseIterable { case png, jpeg }

public struct ExportSettings: Codable, Equatable {
    public var width = 3840
    public var height = 2160
    public var format: ImageFormat = .png
    public var supersampling = true
    public var jpegQuality = 0.95
    public init() {}
    public func validated() throws -> Self {
        guard (64...8192).contains(width), (64...8192).contains(height), width * height <= 40_000_000,
              jpegQuality.isFinite, (0.1...1).contains(jpegQuality) else { throw MandelbrotError.invalidExport }
        return self
    }
}

public struct SavedView: Codable, Equatable {
    public let version: Int
    public var view: ViewState
    public var export: ExportSettings
    public var windowWidth: Double
    public var windowHeight: Double
    public init(view: ViewState, export: ExportSettings, windowWidth: Double, windowHeight: Double) {
        version = 1; self.view = view; self.export = export
        self.windowWidth = windowWidth; self.windowHeight = windowHeight
    }
    public func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> SavedView {
        guard data.count <= 1_048_576 else { throw MandelbrotError.invalidView }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    public func validated() throws -> Self {
        guard version == 1 else { throw MandelbrotError.unsupportedVersion(version) }
        _ = try view.validated(); _ = try export.validated()
        guard windowWidth.isFinite, windowHeight.isFinite, (900...7680).contains(windowWidth),
              (640...4320).contains(windowHeight) else { throw MandelbrotError.invalidWindow }
        return self
    }
}

public struct ViewHistory {
    private var back: [ViewState] = []
    private var forward: [ViewState] = []
    public init() {}
    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }
    public mutating func record(_ state: ViewState) {
        if back.last != state { back.append(state) }
        if back.count > 150 { back.removeFirst() }
        forward.removeAll()
    }
    public mutating func goBack(from current: ViewState) -> ViewState? {
        guard let previous = back.popLast() else { return nil }
        forward.append(current); return previous
    }
    public mutating func goForward(from current: ViewState) -> ViewState? {
        guard let next = forward.popLast() else { return nil }
        back.append(current); return next
    }
}

public enum MandelbrotError: LocalizedError {
    case invalidView, invalidExport, invalidWindow, unsupportedVersion(Int), renderFailed
    public var errorDescription: String? {
        switch self {
        case .invalidView: return "This view contains invalid coordinates, zoom, or detail settings."
        case .invalidExport: return "Use image dimensions from 64 to 8,192 pixels, up to 40 megapixels in total."
        case .invalidWindow: return "The saved window dimensions are outside the supported range."
        case .unsupportedVersion(let version): return "This file uses view format version \(version). This app supports version 1."
        case .renderFailed: return "The image could not be rendered. Try a smaller image size."
        }
    }
}
