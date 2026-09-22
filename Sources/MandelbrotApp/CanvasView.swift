import AppKit
import MandelbrotCore

final class CanvasView: FlippedView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var imageState = ViewState()
    var viewState = ViewState() { didSet { needsDisplay = true } }
    var exportAspect: Double? { didSet { needsDisplay = true } }
    var onGestureStart: (() -> Void)?
    var onZoom: ((Double, Double, Double) -> Void)?
    var onPan: ((Double, Double) -> Void)?
    var onGestureEnd: (() -> Void)?
    var onResize: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onHome: (() -> Void)?
    var onPointer: ((Double, Double) -> Void)?
    private var lastPoint: NSPoint?
    private var tracking: NSTrackingArea?
    private var gestureTimer: Timer?
    private var gestureActive = false
    private var sizeBefore = NSSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = Theme.line.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Mandelbrot set explorer. Drag to pan, scroll or pinch to zoom. Use the View menu for keyboard controls.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func layout() {
        super.layout()
        if bounds.size != sizeBefore { sizeBefore = bounds.size; onResize?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.008, green: 0.045, blue: 0.082, alpha: 1).setFill()
        bounds.fill()
        if let image, let context = NSGraphicsContext.current?.cgContext {
            // Reproject the last completed frame immediately while a fresh render is in flight.
            let scale = bounds.width / viewState.span
            let imageWidth = imageState.span * scale
            let imageHeight = imageWidth * CGFloat(image.height) / CGFloat(image.width)
            let x = bounds.midX + (imageState.centerX - viewState.centerX) * scale - imageWidth / 2
            let y = bounds.midY - (imageState.centerY - viewState.centerY) * scale - imageHeight / 2
            context.saveGState()
            context.translateBy(x: x, y: y + imageHeight)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            context.restoreGState()
        }
        if let aspect = exportAspect, aspect > 0 {
            // Exports preserve horizontal span. Shade any vertical area excluded from the export.
            let h = bounds.width / aspect
            if h < bounds.height {
                let top = (bounds.height - h) / 2
                NSColor.black.withAlphaComponent(0.45).setFill()
                NSRect(x: 0, y: 0, width: bounds.width, height: top).fill()
                NSRect(x: 0, y: top + h, width: bounds.width, height: top).fill()
                let path = NSBezierPath(rect: NSRect(x: 1, y: top, width: bounds.width - 2, height: h))
                Theme.accent.withAlphaComponent(0.7).setStroke()
                path.setLineDash([6, 5], count: 2, phase: 0); path.stroke()
            }
        }
        drawBadge("COMPLEX PLANE", at: NSPoint(x: 18, y: 18), color: Theme.secondary)
        let help = "Drag to pan  ·  Scroll to zoom  ·  Double-click to dive"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.secondary]
        let width = (help as NSString).size(withAttributes: attrs).width
        if bounds.width > width + 60 {
            let rect = NSRect(x: (bounds.width - width - 28) / 2, y: bounds.height - 43, width: width + 28, height: 27)
            Theme.background.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
            (help as NSString).draw(at: NSPoint(x: rect.minX + 14, y: rect.minY + 7), withAttributes: attrs)
        }
    }
    private func drawBadge(_ text: String, at point: NSPoint, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: color, .kern: 1.4]
        let size = (text as NSString).size(withAttributes: attrs)
        Theme.background.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: NSRect(x: point.x - 8, y: point.y - 5, width: size.width + 16, height: 24), xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
    private func beginGesture() {
        gestureTimer?.invalidate()
        if !gestureActive { gestureActive = true; onGestureStart?() }
    }
    private func finishGestureSoon() {
        gestureTimer?.invalidate()
        gestureTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in self?.finishGesture() }
    }
    private func finishGesture() {
        gestureTimer?.invalidate(); gestureTimer = nil
        guard gestureActive else { return }
        gestureActive = false; onGestureEnd?()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        beginGesture()
        if event.clickCount == 2 {
            onZoom?(event.modifierFlags.contains(.option) ? 0.5 : 2, point.x / bounds.width, point.y / bounds.height)
            finishGesture()
        } else { lastPoint = point; NSCursor.closedHand.push() }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lastPoint { onPan?((point.x - lastPoint.x) / bounds.width, (point.y - lastPoint.y) / bounds.height) }
        lastPoint = point
    }
    override func mouseUp(with event: NSEvent) {
        if lastPoint != nil { NSCursor.pop() }
        lastPoint = nil; finishGesture()
    }
    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        beginGesture()
        let point = convert(event.locationInWindow, from: nil)
        let speed = event.hasPreciseScrollingDeltas ? 0.012 : 0.10
        onZoom?(exp(min(0.8, max(-0.8, Double(event.scrollingDeltaY) * speed))), point.x / bounds.width, point.y / bounds.height)
        finishGestureSoon()
    }
    override func magnify(with event: NSEvent) {
        beginGesture()
        let point = convert(event.locationInWindow, from: nil)
        onZoom?(exp(Double(event.magnification) * 1.8), point.x / bounds.width, point.y / bounds.height)
        finishGestureSoon()
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointer?(viewState.centerX + (point.x / bounds.width - 0.5) * viewState.span,
                   viewState.centerY + (0.5 - point.y / bounds.height) * viewState.span * bounds.height / bounds.width)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124, 125, 126:
            beginGesture()
            let step = event.modifierFlags.contains(.shift) ? 0.2 : 0.07
            onPan?(event.keyCode == 123 ? step : event.keyCode == 124 ? -step : 0,
                   event.keyCode == 126 ? step : event.keyCode == 125 ? -step : 0)
            finishGestureSoon()
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": beginGesture(); onZoom?(2, 0.5, 0.5); finishGesture()
            case "-": beginGesture(); onZoom?(0.5, 0.5, 0.5); finishGesture()
            case "0": onHome?()
            case "[": onBack?()
            case "]": onForward?()
            default: super.keyDown(with: event)
            }
        }
    }
}
