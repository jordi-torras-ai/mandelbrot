import AppKit
import MandelbrotCore

final class InspectorView: FlippedView {
    var onDestination: ((Int) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onHome: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onApplyCoordinates: ((String, String, String) -> Void)?
    var onDetail: ((Int) -> Void)?
    var onPalette: ((Palette) -> Void)?
    var onPeriod: ((Double, Bool) -> Void)?
    var onExport: (() -> Void)?
    let zoomLabel = Theme.label("1.00×", size: 35, weight: .light, mono: true)
    let zoomSubtitle = Theme.label("MAGNIFICATION", size: 9, weight: .medium, color: Theme.secondary)
    let destination = NSPopUpButton()
    let realField = Theme.field("-0.6", label: "Real center coordinate")
    let imaginaryField = Theme.field("0", label: "Imaginary center coordinate")
    let spanField = Theme.field("3.4", label: "Horizontal span")
    let detail = NSPopUpButton()
    let palette = NSPopUpButton()
    let swatch = PaletteSwatch()
    let period = NSSlider(value: 120, minValue: 20, maxValue: 500, target: nil, action: nil)
    let periodValue = Theme.label("120", size: 11, color: Theme.secondary, mono: true)
    let exportSummary = Theme.label("3840 × 2160 · PNG", size: 12, mono: true)
    let precisionLabel = Theme.label("Double precision · 64-bit", size: 10, color: Theme.secondary)
    private(set) var backButton: ActionButton!
    private(set) var forwardButton: ActionButton!
    private let contentWidth: CGFloat = 252
    private var periodGesture = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let w = contentWidth
        func put(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            view.frame = NSRect(x: x + 20, y: y, width: width, height: height); addSubview(view)
        }
        func label(_ title: String, _ y: CGFloat) { put(Theme.label(title, size: 10, weight: .semibold, color: Theme.secondary), 0, y, w, 16) }
        func divider(_ y: CGFloat) {
            let v = NSView(frame: NSRect(x: 20, y: y, width: w, height: 1)); v.wantsLayer = true
            v.layer?.backgroundColor = Theme.line.cgColor; addSubview(v)
        }
        put(Theme.label("A closer look", size: 22, weight: .semibold), 0, 20, w, 29)
        put(Theme.label("There is always more to discover.", size: 11, color: Theme.secondary), 0, 53, w, 18)
        label("JUMP TO A PLACE", 96)
        destination.addItems(withTitles: Destination.all.map(\.name))
        destination.addItem(withTitle: "Custom location")
        destination.lastItem?.isEnabled = false
        destination.target = self; destination.action = #selector(destinationChanged)
        destination.setAccessibilityLabel("Interesting locations")
        put(destination, -3, 118, w + 6, 28)
        put(zoomLabel, 0, 170, w, 45)
        put(zoomSubtitle, 2, 218, w, 15)
        let minus = ActionButton("", symbol: "minus") { [weak self] in self?.onZoom?(0.5) }
        minus.toolTip = "Zoom out (−)"; minus.setAccessibilityLabel("Zoom out")
        let plus = ActionButton("", symbol: "plus") { [weak self] in self?.onZoom?(2) }
        plus.toolTip = "Zoom in (+)"; plus.setAccessibilityLabel("Zoom in")
        let home = ActionButton("Reset", symbol: "arrow.counterclockwise") { [weak self] in self?.onHome?() }
        home.toolTip = "Return to the whole set (⌘0)"
        put(minus, -3, 248, 48, 30); put(plus, 48, 248, 48, 30); put(home, 102, 248, 153, 30)
        backButton = ActionButton("Back", symbol: "arrow.left") { [weak self] in self?.onBack?() }
        forwardButton = ActionButton("Forward", symbol: "arrow.right") { [weak self] in self?.onForward?() }
        put(backButton, -3, 284, 126, 28); put(forwardButton, 126, 284, 129, 28)
        divider(333)
        label("POSITION", 353)
        put(Theme.label("Real", size: 11, color: Theme.secondary), 0, 383, 40, 20)
        put(realField, 45, 379, w - 45, 26)
        put(Theme.label("Imag", size: 11, color: Theme.secondary), 0, 417, 40, 20)
        put(imaginaryField, 45, 413, w - 45, 26)
        put(Theme.label("Span", size: 11, color: Theme.secondary), 0, 451, 40, 20)
        put(spanField, 45, 447, w - 45, 26)
        let apply = ActionButton("Go to coordinates", symbol: "location") { [weak self] in
            guard let self else { return }
            self.onApplyCoordinates?(self.realField.stringValue, self.imaginaryField.stringValue, self.spanField.stringValue)
        }
        put(apply, -3, 485, w + 6, 29)
        divider(535)
        label("APPEARANCE", 554)
        put(Theme.label("Palette", size: 11, color: Theme.secondary), 0, 585, 64, 20)
        palette.addItems(withTitles: Palette.allCases.map(\.title))
        palette.target = self; palette.action = #selector(paletteChanged)
        palette.setAccessibilityLabel("Blue color palette")
        put(palette, 68, 579, w - 65, 28)
        put(swatch, 0, 620, w, 14)
        put(Theme.label("Color spread", size: 11, color: Theme.secondary), 0, 651, 120, 20)
        periodValue.alignment = .right
        put(periodValue, w - 55, 651, 55, 20)
        period.isContinuous = true
        period.target = self; period.action = #selector(periodChanged)
        period.setAccessibilityLabel("Color spread")
        put(period, 0, 679, w, 22)
        put(Theme.label("Detail", size: 11, color: Theme.secondary), 0, 717, 56, 20)
        detail.addItems(withTitles: ["400 · Quick", "800 · Standard", "1,600 · Fine", "3,200 · Deep", "6,400 · Ultra", "12,800 · Extreme", "20,000 · Maximum"])
        detail.target = self; detail.action = #selector(detailChanged)
        detail.setAccessibilityLabel("Maximum iterations")
        put(detail, 61, 711, w - 58, 28)
        put(precisionLabel, 0, 752, w, 18)
        divider(787)
        label("MAKE IT YOURS", 807)
        put(exportSummary, 0, 835, w, 21)
        put(Theme.label("Save an image at your chosen size.", size: 11, color: Theme.secondary), 0, 861, w, 18)
        let export = ActionButton("Export image…", symbol: "square.and.arrow.up", primary: true) { [weak self] in self?.onExport?() }
        put(export, -3, 893, w + 6, 32)
        frame.size = NSSize(width: 292, height: 949)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func destinationChanged() {
        if Destination.all.indices.contains(destination.indexOfSelectedItem) { onDestination?(destination.indexOfSelectedItem) }
    }
    @objc private func paletteChanged() { onPalette?(Palette.allCases[palette.indexOfSelectedItem]) }
    @objc private func detailChanged() {
        let values = [400, 800, 1600, 3200, 6400, 12800, 20000]
        let index = detail.indexOfSelectedItem
        if index >= 0, index < values.count { onDetail?(values[index]) }
    }
    @objc private func periodChanged() {
        let event = NSApp.currentEvent
        let ended = event?.type == .leftMouseUp || event?.type == .keyDown
        onPeriod?(period.doubleValue, !periodGesture)
        periodGesture = !ended
        periodValue.stringValue = "\(Int(period.doubleValue))"
    }
    func update(view: ViewState, history: ViewHistory, export: ExportSettings) {
        let zoom = view.zoom
        zoomLabel.stringValue = zoom < 1000 ? String(format: "%.2f×", zoom) : zoom < 1_000_000 ? String(format: "%.1fK×", zoom / 1000) : zoom < 1_000_000_000 ? String(format: "%.2fM×", zoom / 1_000_000) : String(format: "%.2fB×", zoom / 1_000_000_000)
        zoomLabel.toolTip = String(format: "%.12g× magnification", zoom)
        realField.stringValue = String(view.centerX)
        imaginaryField.stringValue = String(view.centerY)
        spanField.stringValue = String(view.span)
        let values = [400, 800, 1600, 3200, 6400, 12800, 20000]
        if detail.numberOfItems > values.count { detail.removeItem(at: values.count) }
        if let index = values.firstIndex(of: view.iterations) { detail.selectItem(at: index) }
        else { detail.addItem(withTitle: "\(view.iterations) · Custom"); detail.selectItem(at: values.count) }
        let paletteIndex = Palette.allCases.firstIndex(of: view.palette)!
        palette.selectItem(at: paletteIndex); swatch.selected = paletteIndex
        period.doubleValue = view.colorPeriod; periodValue.stringValue = "\(Int(view.colorPeriod))"
        backButton.isEnabled = history.canGoBack; forwardButton.isEnabled = history.canGoForward
        if let index = Destination.all.firstIndex(where: { $0.view.centerX == view.centerX && $0.view.centerY == view.centerY && $0.view.span == view.span }) {
            destination.selectItem(at: index)
        } else { destination.selectItem(at: Destination.all.count) }
        exportSummary.stringValue = "\(export.width) × \(export.height) · \(export.format.rawValue.uppercased())"
        precisionLabel.stringValue = view.span <= ViewState.minimumSpan * 1.01 ? "Maximum zoom reached · 64-bit precision" : "Double precision · 64-bit"
    }
}
