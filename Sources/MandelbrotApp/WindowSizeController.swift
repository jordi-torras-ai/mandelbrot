import AppKit

final class WindowSizeController: NSWindowController {
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let preset = NSPopUpButton()
    private let message = Theme.label("", size: 11, color: Theme.secondary)
    var onApply: ((NSSize) -> Void)?
    var onClose: (() -> Void)?
    init(current: NSSize) {
        widthField = Theme.field(String(Int(current.width)), label: "Window content width in points")
        heightField = Theme.field(String(Int(current.height)), label: "Window content height in points")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 305), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Window size"; window.appearance = NSAppearance(named: .darkAqua); window.backgroundColor = Theme.background
        let root = FlippedView(); window.contentView = root
        func put(_ item: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            item.frame = NSRect(x: x, y: y, width: w, height: h); root.addSubview(item)
        }
        put(Theme.label("Room to explore", size: 23, weight: .semibold), 25, 20, 390, 31)
        put(Theme.label("Resize the window or choose precise dimensions.", size: 11, color: Theme.secondary), 26, 60, 390, 20)
        preset.addItems(withTitles: ["Custom size", "Compact · 1000 × 720", "Comfortable · 1360 × 900", "Large · 1680 × 1050", "Wide · 1920 × 1080"])
        preset.target = self; preset.action = #selector(presetChanged)
        preset.setAccessibilityLabel("Window size preset")
        put(preset, 22, 99, 396, 28)
        put(Theme.label("Width", size: 11, color: Theme.secondary), 26, 147, 60, 20)
        put(widthField, 78, 141, 118, 28)
        put(Theme.label("Height", size: 11, color: Theme.secondary), 222, 147, 55, 20)
        put(heightField, 280, 141, 133, 28)
        message.stringValue = "Content size in points, including the inspector.\nMinimum 900 × 640; larger sizes fit to the current screen."
        message.maximumNumberOfLines = 2
        put(message, 26, 188, 390, 39)
        let cancel = ActionButton("Cancel") { [weak self] in self?.dismiss() }
        cancel.keyEquivalent = "\u{1b}"
        let apply = ActionButton("Resize window", primary: true) { [weak self] in self?.apply() }
        apply.keyEquivalent = "\r"
        put(cancel, 188, 258, 90, 30); put(apply, 284, 258, 133, 30)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(on parent: NSWindow) { if let window { parent.beginSheet(window) } }
    @objc private func presetChanged() {
        let sizes = [(0, 0), (1000, 720), (1360, 900), (1680, 1050), (1920, 1080)]
        let index = preset.indexOfSelectedItem
        if index > 0 { widthField.stringValue = String(sizes[index].0); heightField.stringValue = String(sizes[index].1) }
    }
    private func apply() {
        guard let width = Int(widthField.stringValue), let height = Int(heightField.stringValue),
              (900...7680).contains(width), (640...4320).contains(height) else {
            message.stringValue = "Use width 900–7680 and height 640–4320 points."; return
        }
        onApply?(NSSize(width: width, height: height)); dismiss()
    }
    private func dismiss() {
        if let window { window.sheetParent?.endSheet(window); window.orderOut(nil) }; onClose?()
    }
}
