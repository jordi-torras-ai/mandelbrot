import AppKit
import UniformTypeIdentifiers
import MandelbrotCore

final class MainWindowController: NSWindowController, NSWindowDelegate {
    var state = ViewState()
    var exportSettings = ExportSettings()
    private var history = ViewHistory()
    private var savedURL: URL?
    private var savedSnapshot: SavedView?
    private var gestureStart: ViewState?
    private var renderCancellation: RenderCancellation?
    private var renderWork: DispatchWorkItem?
    private let renderQueue = DispatchQueue(label: "app.mandelbrot.preview", qos: .userInitiated)
    private var exportController: ExportWindowController?
    private var sizeController: WindowSizeController?
    private var lastPeriodChange = Date.distantPast
    let root = WorkspaceView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Mandelbrot"
        window.backgroundColor = Theme.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 900, height: 668)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.delegate = self
        window.center()
        wireActions()
        updateInterface()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func wireActions() {
        root.onOpen = { [weak self] in self?.openView() }
        root.onSave = { [weak self] in self?.saveView() }
        root.onExport = { [weak self] in self?.showExport() }
        root.onWindowSize = { [weak self] in self?.showWindowSize() }
        let canvas = root.canvas
        canvas.onResize = { [weak self] in self?.requestRender() }
        canvas.onGestureStart = { [weak self] in self?.gestureStart = self?.state }
        canvas.onGestureEnd = { [weak self] in
            guard let self else { return }
            if let previous = self.gestureStart, previous != self.state { self.history.record(previous) }
            self.gestureStart = nil; self.updateInterface(); self.requestRender()
        }
        canvas.onZoom = { [weak self] factor, x, y in
            guard let self else { return }
            self.state.zoom(by: factor, anchorX: x, anchorY: y, aspect: self.aspect)
            self.didChange()
        }
        canvas.onPan = { [weak self] x, y in
            guard let self else { return }
            self.state.pan(fractionX: x, fractionY: y, aspect: self.aspect)
            self.didChange()
        }
        canvas.onBack = { [weak self] in self?.goBack() }
        canvas.onForward = { [weak self] in self?.goForward() }
        canvas.onHome = { [weak self] in self?.resetView() }
        canvas.onPointer = { [weak self] x, y in self?.root.pointerLabel.stringValue = String(format: "Re %.9g   Im %.9g", x, y) }
        let inspector = root.inspector
        inspector.onZoom = { [weak self] in self?.zoom($0) }
        inspector.onHome = { [weak self] in self?.resetView() }
        inspector.onBack = { [weak self] in self?.goBack() }
        inspector.onForward = { [weak self] in self?.goForward() }
        inspector.onDestination = { [weak self] index in
            guard let self else { return }
            var next = Destination.all[index].view
            next.palette = self.state.palette; next.colorPeriod = self.state.colorPeriod
            self.change(to: next)
        }
        inspector.onApplyCoordinates = { [weak self] x, y, span in
            guard let self else { return }
            guard let x = Double(x), let y = Double(y), let span = Double(span) else {
                self.showError(message: "Enter a number for each coordinate and span. Scientific notation, such as 1e-6, is supported."); return
            }
            var next = self.state; next.centerX = x; next.centerY = y; next.span = span
            do { self.change(to: try next.validated()); self.window?.makeFirstResponder(canvas) }
            catch { self.showError(error) }
        }
        inspector.onDetail = { [weak self] value in
            guard let self else { return }; var next = self.state; next.iterations = value; self.change(to: next)
        }
        inspector.onPalette = { [weak self] value in
            guard let self else { return }; var next = self.state; next.palette = value; self.change(to: next)
        }
        inspector.onPeriod = { [weak self] value, _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastPeriodChange) > 0.5 { self.history.record(self.state) }
            self.lastPeriodChange = Date()
            self.state.colorPeriod = value; self.didChange()
        }
        inspector.onExport = { [weak self] in self?.showExport() }
    }
    private var aspect: Double { max(1, root.canvas.bounds.width) / max(1, root.canvas.bounds.height) }
    private func change(to next: ViewState) {
        guard next != state else { return }
        history.record(state); state = next; didChange()
    }
    private func didChange() { updateInterface(); requestRender() }
    func updateInterface() {
        root.canvas.viewState = state
        root.inspector.update(view: state, history: history, export: exportSettings)
        root.centerLabel.stringValue = String(format: "CENTER  %.10g, %.10g", state.centerX, state.centerY)
        window?.isDocumentEdited = savedSnapshot.map { $0.view != state || $0.export != exportSettings } ?? (state != ViewState())
    }
    func requestRender() {
        renderCancellation?.cancel(); renderWork?.cancel()
        guard root.canvas.bounds.width > 1, root.canvas.bounds.height > 1 else { return }
        let cancellation = RenderCancellation()
        renderCancellation = cancellation
        let view = state
        let scale = window?.backingScaleFactor ?? 2
        let rawWidth = root.canvas.bounds.width * scale
        let rawHeight = root.canvas.bounds.height * scale
        let limit = min(1, sqrt(6_000_000 / (rawWidth * rawHeight)), 8192 / max(rawWidth, rawHeight))
        let width = max(1, Int(rawWidth * limit)), height = max(1, Int(rawHeight * limit))
        root.statusLabel.stringValue = "●  Rendering…"
        root.statusLabel.textColor = Theme.accent
        let work = DispatchWorkItem { [weak self] in
            guard !cancellation.isCancelled else { return }
            do {
                let previewScale = min(1, 560.0 / Double(width))
                let preview = try Renderer.render(view: view, width: max(1, Int(Double(width) * previewScale)),
                                                  height: max(1, Int(Double(height) * previewScale)), cancellation: cancellation)
                if let preview, !cancellation.isCancelled {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.renderCancellation === cancellation, !cancellation.isCancelled else { return }
                        self.root.canvas.imageState = view; self.root.canvas.image = preview.image
                        self.root.statusLabel.stringValue = "●  Refining detail…"
                    }
                }
                guard !cancellation.isCancelled else { return }
                if let final = try Renderer.render(view: view, width: width, height: height, cancellation: cancellation) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.renderCancellation === cancellation, !cancellation.isCancelled else { return }
                        self.root.canvas.imageState = view; self.root.canvas.image = final.image
                        self.root.statusLabel.stringValue = "●  Ready  ·  \(Int(final.seconds * 1000)) ms"
                        self.root.statusLabel.textColor = Theme.mint
                        self.root.resolutionLabel.stringValue = "\(width) × \(height) px"
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.renderCancellation === cancellation else { return }
                    self.root.statusLabel.stringValue = "Render failed"; self.showError(error)
                }
            }
        }
        renderWork = work
        renderQueue.asyncAfter(deadline: .now() + 0.07, execute: work)
    }
    @objc func zoomIn() { zoom(2) }
    @objc func zoomOut() { zoom(0.5) }
    private func zoom(_ factor: Double) { var next = state; next.zoom(by: factor, aspect: aspect); change(to: next) }
    @objc func resetView() {
        var next = ViewState(); next.palette = state.palette; next.colorPeriod = state.colorPeriod; change(to: next)
    }
    @objc func goBack() { if let previous = history.goBack(from: state) { state = previous; didChange() } }
    @objc func goForward() { if let next = history.goForward(from: state) { state = next; didChange() } }

    private func snapshot() -> SavedView {
        let size = window?.contentView?.bounds.size ?? NSSize(width: 1360, height: 900)
        return SavedView(view: state, export: exportSettings, windowWidth: max(900, size.width), windowHeight: max(640, size.height))
    }
    @objc func openView() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Open a saved view"
        panel.allowedContentTypes = [UTType(filenameExtension: "mandelbrot") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }; self?.load(url)
        }
    }
    func load(_ url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 1_048_576 else { throw MandelbrotError.invalidView }
            let document = try SavedView.decode(Data(contentsOf: url))
            history.record(state); state = document.view; exportSettings = document.export
            savedURL = url; savedSnapshot = document
            window?.title = "\(url.deletingPathExtension().lastPathComponent) — Mandelbrot"
            window?.representedURL = url
            setWindowSize(NSSize(width: document.windowWidth, height: document.windowHeight))
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            didChange()
        } catch { showError(error) }
    }
    @objc func saveView() {
        if let savedURL { writeView(to: savedURL) } else { saveViewAs() }
    }
    @objc func saveViewAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Save your place in the set"
        panel.message = "Save the position, palette, detail, window size, and export settings."
        panel.nameFieldStringValue = savedURL?.lastPathComponent ?? "Untitled.mandelbrot"
        panel.allowedContentTypes = [UTType(filenameExtension: "mandelbrot") ?? .json]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }; self?.writeView(to: url)
        }
    }
    private func writeView(to url: URL) {
        do {
            let document = snapshot()
            try document.encoded().write(to: url, options: .atomic)
            savedURL = url; savedSnapshot = document
            window?.title = "\(url.deletingPathExtension().lastPathComponent) — Mandelbrot"
            window?.representedURL = url
            window?.isDocumentEdited = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            root.statusLabel.stringValue = "●  View saved"
        } catch { showError(error) }
    }
    @objc func showExport() {
        guard let window, window.attachedSheet == nil else { return }
        let controller = ExportWindowController(view: state, settings: exportSettings, viewportAspect: aspect)
        exportController = controller
        controller.onSettingsChanged = { [weak self] settings in self?.exportSettings = settings; self?.updateInterface() }
        controller.onClose = { [weak self] in self?.exportController = nil }
        controller.present(on: window)
    }
    @objc func showWindowSize() {
        guard let window, window.attachedSheet == nil else { return }
        let controller = WindowSizeController(current: root.bounds.size)
        sizeController = controller
        controller.onApply = { [weak self] size in self?.setWindowSize(size) }
        controller.onClose = { [weak self] in self?.sizeController = nil }
        controller.present(on: window)
    }
    func setWindowSize(_ size: NSSize) {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        let decoration = window.frame.height - root.bounds.height
        let available = screen?.visibleFrame.size ?? NSSize(width: 1920, height: 1080)
        let clamped = NSSize(width: max(900, min(size.width, available.width)), height: max(640, min(size.height, available.height - decoration)))
        window.setContentSize(clamped)
        if let visible = screen?.visibleFrame {
            var frame = window.frame
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            window.setFrame(frame, display: true)
        }
        requestRender()
    }
    @objc func toggleFullScreen() { window?.toggleFullScreen(nil) }
    func windowDidResize(_ notification: Notification) { requestRender() }
    func windowDidChangeBackingProperties(_ notification: Notification) { requestRender() }
    func windowWillClose(_ notification: Notification) { renderCancellation?.cancel(); renderWork?.cancel() }
    func showError(_ error: Error) { showError(message: error.localizedDescription) }
    func showError(message: String) {
        let alert = NSAlert(); alert.messageText = "A little course correction"; alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

final class WorkspaceView: FlippedView {
    let canvas = CanvasView(frame: .zero)
    let inspector = InspectorView(frame: .zero)
    let scroll = NSScrollView()
    let title = Theme.label("Mandelbrot", size: 21, weight: .semibold)
    let subtitle = Theme.label("AN EXPLORATION OF THE INFINITE", size: 9, weight: .medium, color: Theme.secondary)
    let mark = Theme.label("◉", size: 28, color: Theme.accent)
    let statusLabel = Theme.label("●  Preparing your view…", size: 11, color: Theme.mint)
    let pointerLabel = Theme.label("", size: 10, color: Theme.secondary, mono: true)
    let centerLabel = Theme.label("", size: 10, color: Theme.secondary, mono: true)
    let resolutionLabel = Theme.label("", size: 10, color: Theme.secondary, mono: true)
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?
    var onExport: (() -> Void)?
    var onWindowSize: (() -> Void)?
    private var open: ActionButton!
    private var save: ActionButton!
    private var export: ActionButton!
    private var size: ActionButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = Theme.background.cgColor
        [mark, title, subtitle, canvas, statusLabel, pointerLabel, centerLabel, resolutionLabel].forEach(addSubview)
        open = ActionButton("Open", symbol: "folder") { [weak self] in self?.onOpen?() }
        save = ActionButton("Save view", symbol: "bookmark") { [weak self] in self?.onSave?() }
        export = ActionButton("Export image", symbol: "square.and.arrow.up", primary: true) { [weak self] in self?.onExport?() }
        size = ActionButton("Window size", symbol: "macwindow") { [weak self] in self?.onWindowSize?() }
        [size, open, save, export].forEach { addSubview($0!) }
        scroll.documentView = inspector
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true; scroll.layer?.backgroundColor = Theme.panel.cgColor
        scroll.layer?.cornerRadius = 12; scroll.layer?.borderWidth = 1; scroll.layer?.borderColor = Theme.line.cgColor
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        mark.frame = NSRect(x: 21, y: 13, width: 37, height: 38)
        title.frame = NSRect(x: 63, y: 11, width: 200, height: 28)
        subtitle.frame = NSRect(x: 64, y: 41, width: 260, height: 14)
        export.frame = NSRect(x: w - 155, y: 19, width: 139, height: 32)
        save.frame = NSRect(x: w - 270, y: 19, width: 110, height: 32)
        open.frame = NSRect(x: w - 359, y: 19, width: 84, height: 32)
        size.frame = NSRect(x: w - 489, y: 19, width: 125, height: 32)
        let canvasWidth = max(200, w - 340)
        canvas.frame = NSRect(x: 18, y: 74, width: canvasWidth, height: max(100, h - 119))
        scroll.frame = NSRect(x: w - 308, y: 74, width: 290, height: max(100, h - 119))
        statusLabel.frame = NSRect(x: 22, y: h - 31, width: 205, height: 18)
        pointerLabel.frame = NSRect(x: 240, y: h - 30, width: max(0, canvasWidth - 390), height: 17)
        resolutionLabel.alignment = .right
        resolutionLabel.frame = NSRect(x: canvasWidth - 120, y: h - 30, width: 135, height: 17)
        centerLabel.frame = NSRect(x: w - 300, y: h - 30, width: 283, height: 17)
    }
}
