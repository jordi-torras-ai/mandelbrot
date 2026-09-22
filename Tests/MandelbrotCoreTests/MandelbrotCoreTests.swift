import AppKit
import FractalEngine
import MandelbrotCore

final class MandelbrotCoreTests {
    func testKnownInteriorAndExteriorPoints() {
        expectEqual(mdb_escape(0, 0, 800), -1)
        expectEqual(mdb_escape(-1, 0, 800), -1)
        expectEqual(mdb_escape(-0.25, 0.25, 800), -1)
        expectGreater(mdb_escape(1, 1, 800), 0)
        expectGreater(mdb_escape(-2, 1, 800), 0)
        expectGreater(mdb_escape(0.5, 0, 800), 0)
    }

    func testConjugateSymmetry() {
        for x in stride(from: -2.1, through: 0.8, by: 0.1) {
            for y in stride(from: 0.05, through: 1.2, by: 0.1) {
                expectEqual(mdb_escape(x, y, 1200), mdb_escape(x, -y, 1200), accuracy: 1e-12)
            }
        }
    }

    func testCursorAnchoredZoomKeepsComplexPointFixed() {
        var view = ViewState()
        let x = 0.23, y = 0.81, aspect = 1.73
        let real = view.centerX + (x - 0.5) * view.span
        let imaginary = view.centerY + (0.5 - y) * view.span / aspect
        view.zoom(by: 4.5, anchorX: x, anchorY: y, aspect: aspect)
        expectEqual(view.centerX + (x - 0.5) * view.span, real, accuracy: 1e-14)
        expectEqual(view.centerY + (0.5 - y) * view.span / aspect, imaginary, accuracy: 1e-14)
        view.zoom(by: 1 / 4.5, anchorX: x, anchorY: y, aspect: aspect)
        expectEqual(view.centerX, ViewState().centerX, accuracy: 1e-14)
        expectEqual(view.centerY, 0, accuracy: 1e-14)
        expectEqual(view.span, 3.4, accuracy: 1e-14)
    }

    func testPanUsesViewportAspectAndIsReversible() {
        var view = ViewState()
        view.pan(fractionX: 0.25, fractionY: 0.25, aspect: 2)
        expectEqual(view.centerX, -1.45, accuracy: 1e-14)
        expectEqual(view.centerY, 0.425, accuracy: 1e-14)
        view.pan(fractionX: -0.25, fractionY: -0.25, aspect: 2)
        expectEqual(view.centerX, -0.6, accuracy: 1e-14)
        expectEqual(view.centerY, 0, accuracy: 1e-14)
    }

    func testZoomBoundsAndInvalidFactors() {
        var view = ViewState()
        view.zoom(by: 1e100)
        expectEqual(view.span, ViewState.minimumSpan)
        view.zoom(by: 1e-100)
        expectEqual(view.span, ViewState.maximumSpan)
        let valid = view
        for factor in [0.0, -1, .infinity, .nan] { view.zoom(by: factor) }
        expectEqual(view, valid)
    }

    func testHistoryRoundTripAndBranching() {
        var history = ViewHistory()
        let start = ViewState()
        var second = start; second.zoom(by: 2)
        var third = second; third.zoom(by: 3)
        history.record(start); history.record(second)
        expectEqual(history.goBack(from: third), second)
        expectEqual(history.goBack(from: second), start)
        expectFalse(history.canGoBack)
        expectEqual(history.goForward(from: start), second)
        history.record(second)
        expectFalse(history.canGoForward)
        expectEqual(history.goBack(from: third), second)
    }

    func testSavedViewPreservesFullPrecisionAndAllSettings() throws {
        var view = Destination.all.last!.view
        view.palette = .arctic; view.colorPeriod = 231.7
        var settings = ExportSettings()
        settings.width = 7680; settings.height = 4320; settings.format = .jpeg
        settings.jpegQuality = 0.87; settings.supersampling = false
        let document = SavedView(view: view, export: settings, windowWidth: 1360, windowHeight: 900)
        let decoded = try SavedView.decode(document.encoded())
        expectEqual(document, decoded)
        expectEqual(view.centerX.bitPattern, decoded.view.centerX.bitPattern)
        expectEqual(view.centerY.bitPattern, decoded.view.centerY.bitPattern)
    }

    func testRejectsInvalidAndUnsupportedFiles() throws {
        let original = SavedView(view: ViewState(), export: ExportSettings(), windowWidth: 1360, windowHeight: 900)
        var json = try unwrap(JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        json["version"] = 99
        expectThrows(try SavedView.decode(JSONSerialization.data(withJSONObject: json)))
        json["version"] = 1
        var view = try unwrap(json["view"] as? [String: Any]); view["span"] = 0; json["view"] = view
        expectThrows(try SavedView.decode(JSONSerialization.data(withJSONObject: json)))
        expectThrows(try SavedView.decode(Data("not JSON".utf8)))
        expectThrows(try SavedView.decode(Data(repeating: 0, count: 1_048_577)))
        var invalid = original; invalid.view.centerX = .infinity
        expectThrows(try invalid.encoded())
        invalid = original; invalid.windowHeight = -1
        expectThrows(try invalid.encoded())
    }

    func testRejectsOversizedExportAndAccepts8K() throws {
        var settings = ExportSettings()
        settings.width = 7680; settings.height = 4320
        expectNoThrow(try settings.validated())
        settings.width = 8192; settings.height = 8192
        expectThrows(try settings.validated())
        settings.width = Int.max
        expectThrows(try settings.validated())
        settings.width = 64; settings.height = 0
        expectThrows(try settings.validated())
    }

    func testPNGAndJPEGAreRealImagesAtRequestedDimensions() throws {
        let rendered = try unwrap(Renderer.render(view: ViewState(), width: 320, height: 200, samples: 2))
        for format in ImageFormat.allCases {
            let data = try rendered.encoded(format: format)
            let bitmap = try unwrap(NSBitmapImageRep(data: data))
            expectEqual(bitmap.pixelsWide, 320)
            expectEqual(bitmap.pixelsHigh, 200)
            if format == .png { expectEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10]) }
            else { expectEqual(Array(data.prefix(2)), [255, 216]) }
            let inside = try unwrap(bitmap.colorAt(x: 200, y: 100)?.usingColorSpace(.deviceRGB))
            expectLess(inside.redComponent + inside.greenComponent + inside.blueComponent, 0.03)
            let outside = try unwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            expectGreater(outside.blueComponent, outside.redComponent)
        }
    }

    func testRenderingIsDeterministicAndVerticallySymmetric() throws {
        let first = try unwrap(Renderer.render(view: ViewState(), width: 101, height: 81))
        let second = try unwrap(Renderer.render(view: ViewState(), width: 101, height: 81))
        expectEqual(try first.encoded(format: .png), try second.encoded(format: .png))
        let bytes = try unwrap(first.image.dataProvider?.data) as Data
        for y in 0..<40 {
            for x in 0..<101 {
                let top = (y * 101 + x) * 4, bottom = ((80 - y) * 101 + x) * 4
                expectEqual(bytes[top..<top + 4], bytes[bottom..<bottom + 4])
            }
        }
    }

    func testCancellationBeforeAndDuringRendering() throws {
        let cancelled = RenderCancellation(); cancelled.cancel()
        expectNil(try Renderer.render(view: ViewState(), width: 100, height: 100, cancellation: cancelled))
        let live = RenderCancellation()
        let result = try Renderer.render(view: Destination.all.last!.view, width: 500, height: 300, cancellation: live) { _ in live.cancel() }
        expectNil(result)
        expectTrue(live.isCancelled)
    }
}
