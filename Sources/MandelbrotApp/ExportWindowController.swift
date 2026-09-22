import AppKit
import UniformTypeIdentifiers
import MandelbrotCore

final class ExportWindowController: NSWindowController, NSTextFieldDelegate {
    private let view: ViewState
    private var settings: ExportSettings
    private let viewportAspect: Double
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let preset = NSPopUpButton()
    private let format = NSSegmentedControl(labels: ["PNG", "JPEG"], trackingMode: .selectOne, target: nil, action: nil)
    private let antialias = NSButton(checkboxWithTitle: "Smooth edges (4 samples per pixel)", target: nil, action: nil)
    private let quality = NSSlider(value: 0.95, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let qualityLabel = Theme.label("JPEG quality  95%", size: 11, color: Theme.secondary)
    private let preview = NSImageView()
    private let dimensionsLabel = Theme.label("", size: 11, color: Theme.secondary, mono: true)
    private let progress = NSProgressIndicator()
    private let status = Theme.label("", size: 11, color: Theme.secondary)
    private var exportButton: ActionButton!
    private var closeButton: ActionButton!
    private var revealButton: ActionButton!
    private var swapButton: ActionButton!
    private var previewCancellation: RenderCancellation?
    private var exportCancellation: RenderCancellation?
    private var outputURL: URL?
    private var rendering = false
    private let previewQueue = DispatchQueue(label: "app.mandelbrot.export-preview", qos: .userInitiated)
    var onSettingsChanged: ((ExportSettings) -> Void)?
    var onClose: (() -> Void)?

    init(view: ViewState, settings: ExportSettings, viewportAspect: Double) {
        self.view = view; self.settings = settings; self.viewportAspect = viewportAspect
        widthField = Theme.field(String(settings.width), label: "Export width in pixels")
        heightField = Theme.field(String(settings.height), label: "Export height in pixels")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 690), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Export image"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.background
        let root = FlippedView(); window.contentView = root
        func put(_ item: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            item.frame = NSRect(x: x, y: y, width: w, height: h); root.addSubview(item)
        }
        put(Theme.label("A piece of infinity.", size: 25, weight: .semibold), 28, 22, 590, 35)
        put(Theme.label("Your current view, rendered at the size you choose.", size: 12, color: Theme.secondary), 29, 62, 590, 20)
        preset.addItems(withTitles: ["Custom dimensions", "Match explorer aspect", "Full HD · 1920 × 1080", "QHD · 2560 × 1440", "4K · 3840 × 2160", "5K · 5120 × 2880", "8K · 7680 × 4320", "Square · 3000 × 3000", "Ultrawide · 3440 × 1440"])
        preset.selectItem(at: 0); preset.target = self; preset.action = #selector(presetChanged)
        preset.setAccessibilityLabel("Export size preset")
        put(preset, 25, 100, 352, 28)
        put(format, 433, 99, 200, 29)
        format.selectedSegment = settings.format == .png ? 0 : 1
        format.target = self; format.action = #selector(settingsChanged)
        format.setAccessibilityLabel("Image file format")
        put(Theme.label("WIDTH", size: 9, weight: .medium, color: Theme.secondary), 29, 143, 110, 16)
        put(Theme.label("HEIGHT", size: 9, weight: .medium, color: Theme.secondary), 184, 143, 110, 16)
        put(widthField, 28, 163, 128, 29)
        put(Theme.label("×", size: 16, color: Theme.secondary), 166, 167, 20, 23)
        put(heightField, 184, 163, 128, 29)
        let swap = ActionButton("", symbol: "arrow.left.arrow.right") { [weak self] in
            guard let self else { return }
            let old = self.widthField.stringValue; self.widthField.stringValue = self.heightField.stringValue
            self.heightField.stringValue = old; self.preset.selectItem(at: 0); self.settingsChanged()
        }
        swap.setAccessibilityLabel("Swap width and height")
        swapButton = swap
        put(swap, 321, 162, 48, 31)
        widthField.target = self; widthField.action = #selector(dimensionsChanged)
        heightField.target = self; heightField.action = #selector(dimensionsChanged)
        widthField.delegate = self; heightField.delegate = self
        put(qualityLabel, 438, 144, 190, 18)
        quality.doubleValue = settings.jpegQuality
        quality.target = self; quality.action = #selector(settingsChanged)
        quality.setAccessibilityLabel("JPEG quality")
        put(quality, 438, 169, 190, 20)
        antialias.state = settings.supersampling ? .on : .off
        antialias.font = .systemFont(ofSize: 12)
        antialias.target = self; antialias.action = #selector(settingsChanged)
        put(antialias, 28, 210, 420, 22)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true; preview.layer?.backgroundColor = NSColor.black.cgColor
        preview.layer?.cornerRadius = 9; preview.layer?.masksToBounds = true
        preview.layer?.borderWidth = 1; preview.layer?.borderColor = Theme.line.cgColor
        preview.setAccessibilityLabel("Preview of the exported image framing")
        put(preview, 28, 249, 604, 266)
        put(dimensionsLabel, 28, 526, 600, 20)
        let note = Theme.label("The center and horizontal span stay fixed. Changing the aspect ratio\nreveals more or less of the set above and below.", size: 11, color: Theme.secondary)
        note.maximumNumberOfLines = 2
        put(note, 28, 551, 604, 35)
        progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.style = .bar; progress.isHidden = true
        put(progress, 28, 601, 604, 7)
        put(status, 28, 619, 400, 20)
        closeButton = ActionButton("Done") { [weak self] in self?.dismiss() }
        closeButton.keyEquivalent = "\u{1b}"
        exportButton = ActionButton("Save image…", symbol: "square.and.arrow.up", primary: true) { [weak self] in self?.chooseDestination() }
        exportButton.keyEquivalent = "\r"
        revealButton = ActionButton("Show in Finder", symbol: "folder") { [weak self] in
            if let url = self?.outputURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        revealButton.isHidden = true
        put(revealButton, 25, 651, 151, 30)
        put(closeButton, 398, 647, 90, 32)
        put(exportButton, 492, 647, 143, 32)
        updateFormat(); requestPreview()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(on parent: NSWindow) { if let window { parent.beginSheet(window) } }
    private func readSettings() throws -> ExportSettings {
        guard let width = Int(widthField.stringValue), let height = Int(heightField.stringValue) else { throw MandelbrotError.invalidExport }
        var result = settings
        result.width = width; result.height = height
        result.format = format.selectedSegment == 0 ? .png : .jpeg
        result.supersampling = antialias.state == .on
        result.jpegQuality = quality.doubleValue
        return try result.validated()
    }
    @objc private func presetChanged() {
        let sizes: [(Int, Int)] = [(settings.width, settings.height), (3840, min(8192, max(64, Int(3840 / viewportAspect)))),
                                  (1920, 1080), (2560, 1440), (3840, 2160), (5120, 2880), (7680, 4320), (3000, 3000), (3440, 1440)]
        let size = sizes[preset.indexOfSelectedItem]
        widthField.stringValue = String(size.0); heightField.stringValue = String(size.1); settingsChanged()
    }
    @objc private func dimensionsChanged() { preset.selectItem(at: 0); settingsChanged() }
    func controlTextDidChange(_ notification: Notification) { dimensionsChanged() }
    @objc private func settingsChanged() {
        guard !rendering else { return }
        updateFormat()
        do {
            settings = try readSettings(); status.stringValue = ""; exportButton.isEnabled = true
            onSettingsChanged?(settings); requestPreview()
        } catch { status.stringValue = error.localizedDescription; exportButton.isEnabled = false }
    }
    private func updateFormat() {
        quality.isEnabled = format.selectedSegment == 1 && !rendering
        qualityLabel.textColor = format.selectedSegment == 1 ? Theme.secondary : Theme.secondary.withAlphaComponent(0.45)
        qualityLabel.stringValue = "JPEG quality  \(Int(quality.doubleValue * 100))%"
    }
    private func requestPreview() {
        previewCancellation?.cancel()
        let cancellation = RenderCancellation(); previewCancellation = cancellation
        let view = view, settings = settings
        dimensionsLabel.stringValue = "\(settings.width) × \(settings.height) px  ·  \(String(format: "%.1f", Double(settings.width * settings.height) / 1_000_000)) MP  ·  \(settings.format.rawValue.uppercased())"
        let scale = min(604.0 / Double(settings.width), 266.0 / Double(settings.height))
        previewQueue.async {
            let result = try? Renderer.render(view: view, width: max(1, Int(Double(settings.width) * scale)),
                                               height: max(1, Int(Double(settings.height) * scale)), cancellation: cancellation)
            DispatchQueue.main.async { [weak self] in
                guard let self, !cancellation.isCancelled, let result else { return }
                self.preview.image = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
            }
        }
    }
    private func chooseDestination() {
        guard let window, !rendering else { return }
        window.makeFirstResponder(nil)
        do { settings = try readSettings() } catch { showError(error); return }
        onSettingsChanged?(settings)
        let panel = NSSavePanel()
        panel.title = "Save Mandelbrot image"
        panel.allowedContentTypes = [settings.format == .png ? .png : .jpeg]
        panel.nameFieldStringValue = "Mandelbrot-\(settings.width)x\(settings.height).\(settings.format.rawValue == "png" ? "png" : "jpg")"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }; self?.startExport(to: url)
        }
    }
    private func startExport(to url: URL) {
        rendering = true; setControls(enabled: false)
        previewCancellation?.cancel()
        let cancellation = RenderCancellation(); exportCancellation = cancellation
        progress.doubleValue = 0; progress.isHidden = false
        status.stringValue = "Rendering image… 0%"
        revealButton.isHidden = true; closeButton.title = "Cancel"
        let view = view, settings = settings
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                var lastPercent = -1
                let image = try Renderer.render(view: view, width: settings.width, height: settings.height,
                                                 samples: settings.supersampling ? 2 : 1, cancellation: cancellation) { fraction in
                    let percent = Int(fraction * 100)
                    guard percent != lastPercent else { return }; lastPercent = percent
                    DispatchQueue.main.async { [weak self] in
                        guard !cancellation.isCancelled else { return }
                        self?.progress.doubleValue = fraction
                        self?.status.stringValue = percent == 100 ? "Encoding image…" : "Rendering image… \(percent)%"
                    }
                }
                guard let image, !cancellation.isCancelled else { return }
                let data = try image.encoded(format: settings.format, jpegQuality: settings.jpegQuality)
                guard !cancellation.isCancelled else { return }
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !cancellation.isCancelled else { return }
                    self.rendering = false; self.setControls(enabled: true); self.closeButton.title = "Done"
                    self.progress.isHidden = true; self.outputURL = url
                    self.status.stringValue = "Saved · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
                    self.revealButton.isHidden = false
                    self.exportCancellation = nil
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !cancellation.isCancelled else { return }
                    self.rendering = false; self.setControls(enabled: true); self.closeButton.title = "Done"
                    self.progress.isHidden = true; self.status.stringValue = "Export failed"; self.showError(error)
                }
            }
        }
    }
    private func setControls(enabled: Bool) {
        [widthField, heightField, preset, format, antialias, exportButton, swapButton].forEach { $0?.isEnabled = enabled }
        updateFormat()
    }
    private func dismiss() {
        if rendering {
            exportCancellation?.cancel(); exportCancellation = nil
            rendering = false; setControls(enabled: true)
            closeButton.title = "Done"; progress.isHidden = true; status.stringValue = "Export cancelled"
            requestPreview(); return
        }
        if let valid = try? readSettings() { onSettingsChanged?(valid) }
        previewCancellation?.cancel()
        if let window { window.sheetParent?.endSheet(window); window.orderOut(nil) }
        onClose?()
    }
    private func showError(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Unable to export"; alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }
}
