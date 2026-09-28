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

    func testDoubleDoubleParsingFormattingAndArithmetic() throws {
        let text = "-0.743643887037158704752191506114774"
        let value = try unwrap(DoubleDouble(text))
        expectEqual(value.hi, -0.7436438870371587)
        expectEqual(value.lo, -3.628952515063387e-17, accuracy: 1e-31)
        // 33 digits is slightly more than double-double holds, so compare values rather than strings.
        expectEqual(try unwrap(DoubleDouble(value.formatted())), value)
        expectEqual(String(value.formatted().prefix(33)), String(text.prefix(33)))
        expectEqual(value.formatted(tolerance: 1e-9), "-0.743643887")
        expectEqual(try unwrap(DoubleDouble("-0.6")).formatted(tolerance: 1e-12), "-0.6")
        expectEqual(try unwrap(DoubleDouble("1.25e-20")).formatted(), "1.25e-20")
        expectEqual(try unwrap(DoubleDouble("+42")).formatted(), "42")
        expectEqual(DoubleDouble(0).formatted(), "0")
        for invalid in ["", "-", ".", "abc", "1.2.3", "1e", "1e5000", "0x10"] { expectNil(DoubleDouble(invalid)) }
        // 1/3 * 3 is exact to double-double precision, far beyond what a double can tell apart.
        let third = DoubleDouble(1) / DoubleDouble(3)
        expectEqual(((third * DoubleDouble(3)) - DoubleDouble(1)).hi, 0, accuracy: 1e-31)
        expectEqual((value + DoubleDouble(1e-25) - value).hi, 1e-25, accuracy: 1e-31)
    }

    func testDoubleDoubleEscapeMatchesDoubleAndResolvesDeepDetail() throws {
        for x in stride(from: -2.1, through: 0.8, by: 0.23) {
            for y in stride(from: -1.2, through: 1.2, by: 0.19) {
                expectEqual(mdb_escape_dd(x, 0, y, 0, 1200), mdb_escape(x, y, 1200), accuracy: 1e-6)
            }
        }
        // Checked against a 50-digit decimal reference: this point escapes after 17,115 iterations.
        let deepX = try unwrap(DoubleDouble("-0.743643887037158704752191506114774")) + DoubleDouble(-13 * 3e-28)
        let deepY = try unwrap(DoubleDouble("0.131825904205311970493132056385139")) + DoubleDouble(13 * 3e-28 * 0.7)
        expectEqual(mdb_escape_dd(deepX.hi, deepX.lo, deepY.hi, deepY.lo, 20000), 17113.53, accuracy: 0.05)

        var view = ViewState()
        view.preciseCenterX = try unwrap(DoubleDouble("-0.743643887037158704752191506114774"))
        view.preciseCenterY = try unwrap(DoubleDouble("0.131825904205311970493132056385139"))
        view.span = 1e-21; view.iterations = 12800
        expectTrue(view.usesDoubleDouble)
        let image = try unwrap(Renderer.render(view: view, width: 48, height: 32)).image
        let bytes = try unwrap(image.dataProvider?.data) as Data
        let colors = Set(stride(from: 0, to: bytes.count, by: 4).map { bytes[$0..<$0 + 3] })
        // A double-only render collapses every pixel to one point, and so one color.
        expectGreater(colors.count, 200)
    }

    func testDeepZoomAndPanStayExactAndOlderFilesStillOpen() throws {
        var view = ViewState()
        view.preciseCenterX = try unwrap(DoubleDouble("-0.743643887037158704752191506114774"))
        view.span = 1e-20
        let start = view.preciseCenterX
        let x = 0.23, aspect = 1.5
        let anchored = view.preciseCenterX + DoubleDouble((x - 0.5) * view.span)
        view.zoom(by: 1000, anchorX: x, anchorY: 0.5, aspect: aspect)
        expectEqual((view.preciseCenterX + DoubleDouble((x - 0.5) * view.span) - anchored).hi, 0, accuracy: 1e-31)
        view.pan(fractionX: 0.3, fractionY: 0, aspect: aspect)
        view.pan(fractionX: -0.3, fractionY: 0, aspect: aspect)
        view.zoom(by: 1 / 1000, anchorX: x, anchorY: 0.5, aspect: aspect)
        expectEqual((view.preciseCenterX - start).hi, 0, accuracy: 1e-32)
        view.zoom(by: 1e100)
        expectEqual(view.span, ViewState.minimumSpan)
        expectNoThrow(try view.validated())

        let saved = SavedView(view: view, export: ExportSettings(), windowWidth: 1360, windowHeight: 900)
        let decoded = try SavedView.decode(saved.encoded())
        expectEqual(decoded.view.centerXLow.bitPattern, view.centerXLow.bitPattern)
        expectEqual(decoded.view.preciseCenterX, view.preciseCenterX)

        var json = try unwrap(JSONSerialization.jsonObject(with: saved.encoded()) as? [String: Any])
        var old = try unwrap(json["view"] as? [String: Any])
        old["centerXLow"] = nil; old["centerYLow"] = nil; json["view"] = old
        let legacy = try SavedView.decode(JSONSerialization.data(withJSONObject: json))
        expectEqual(legacy.view.centerX, view.centerX)
        expectEqual(legacy.view.centerXLow, 0)

        old["centerXLow"] = 1.0; json["view"] = old  // not a valid low part for this center
        expectThrows(try SavedView.decode(JSONSerialization.data(withJSONObject: json)))
    }
}
