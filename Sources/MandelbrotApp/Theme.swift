import AppKit

enum Theme {
    static let background = NSColor(red: 0.031, green: 0.047, blue: 0.067, alpha: 1)
    static let panel = NSColor(red: 0.050, green: 0.071, blue: 0.098, alpha: 1)
    static let line = NSColor(red: 0.13, green: 0.18, blue: 0.23, alpha: 1)
    static let text = NSColor(red: 0.88, green: 0.93, blue: 0.98, alpha: 1)
    static let secondary = NSColor(red: 0.46, green: 0.56, blue: 0.66, alpha: 1)
    static let accent = NSColor(red: 0.35, green: 0.67, blue: 1, alpha: 1)
    static let mint = NSColor(red: 0.39, green: 0.80, blue: 0.75, alpha: 1)

    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                      color: NSColor = Theme.text, mono: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }
    static func field(_ value: String, label: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = text
        field.backgroundColor = background
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.setAccessibilityLabel(label)
        return field
    }
    static func line(in view: NSView, y: CGFloat, width: CGFloat) {
        let line = NSView(frame: NSRect(x: 0, y: y, width: width, height: 1))
        line.wantsLayer = true; line.layer?.backgroundColor = Theme.line.cgColor
        line.autoresizingMask = [.width]
        view.addSubview(line)
    }
}

class FlippedView: NSView { override var isFlipped: Bool { true } }

final class ActionButton: NSButton {
    var handler: (() -> Void)?
    init(_ title: String, symbol: String? = nil, primary: Bool = false, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        contentTintColor = primary ? .white : Theme.text
        if primary { bezelColor = NSColor(red: 0.12, green: 0.36, blue: 0.63, alpha: 1) }
        target = self; self.action = #selector(run)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { handler?() }
}

final class PaletteSwatch: NSView {
    var selected = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let colors: [[NSColor]] = [
            [.black, NSColor(red: 0.01, green: 0.10, blue: 0.18, alpha: 1), NSColor(red: 0.19, green: 0.33, blue: 0.44, alpha: 1), NSColor(red: 0.87, green: 0.94, blue: 0.98, alpha: 1)],
            [.black, NSColor(red: 0.01, green: 0.06, blue: 0.18, alpha: 1), NSColor(red: 0.09, green: 0.34, blue: 0.64, alpha: 1), NSColor(red: 0.87, green: 0.95, blue: 1, alpha: 1)],
            [.black, NSColor(red: 0.01, green: 0.09, blue: 0.14, alpha: 1), NSColor(red: 0.12, green: 0.38, blue: 0.46, alpha: 1), NSColor(red: 0.89, green: 0.98, blue: 0.98, alpha: 1)]
        ]
        NSGradient(colors: colors[selected])?.draw(in: NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5), angle: 0)
    }
}
