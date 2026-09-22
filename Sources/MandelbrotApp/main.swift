import AppKit
import MandelbrotCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainWindowController?
    private var pendingURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController(); self.controller = controller
        buildMenus(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeFirstResponder(controller.root.canvas)
        if let url = pendingURLs.last { controller.load(url) }
        controller.requestRender()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let url = filenames.last.map({ URL(fileURLWithPath: $0) }) {
            if let controller { controller.load(url) } else { pendingURLs.append(url) }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func buildMenus(_ target: MainWindowController) {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu; return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ selector: Selector?, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command, to object: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers; item.target = object ?? target
            menu.addItem(item)
        }
        let app = menu("Mandelbrot")
        add(app, "About Mandelbrot", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: NSApp)
        app.addItem(.separator())
        add(app, "Hide Mandelbrot", #selector(NSApplication.hide(_:)), "h", to: NSApp)
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option], to: NSApp)
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)), to: NSApp)
        app.addItem(.separator())
        add(app, "Quit Mandelbrot", #selector(NSApplication.terminate(_:)), "q", to: NSApp)
        let file = menu("File")
        add(file, "Open View…", #selector(MainWindowController.openView), "o")
        add(file, "Save View", #selector(MainWindowController.saveView), "s")
        add(file, "Save View As…", #selector(MainWindowController.saveViewAs), "s", modifiers: [.command, .shift])
        file.addItem(.separator())
        add(file, "Export Image…", #selector(MainWindowController.showExport), "e")
        file.addItem(.separator())
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w", to: target.window)
        let edit = menu("Edit")
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); edit.addItem(item)
        }
        let view = menu("View")
        add(view, "Zoom In", #selector(MainWindowController.zoomIn), "=")
        add(view, "Zoom Out", #selector(MainWindowController.zoomOut), "-")
        add(view, "Reset View", #selector(MainWindowController.resetView), "0")
        view.addItem(.separator())
        add(view, "Back", #selector(MainWindowController.goBack), "[")
        add(view, "Forward", #selector(MainWindowController.goForward), "]")
        view.addItem(.separator())
        add(view, "Window Size…", #selector(MainWindowController.showWindowSize), "r", modifiers: [.command, .option])
        add(view, "Enter Full Screen", #selector(MainWindowController.toggleFullScreen), "f", modifiers: [.command, .control])
        let window = menu("Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", to: target.window)
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)), to: target.window)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }
}

// Small headless render command for repeatable image/packaging checks, using the same engine as the app.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render" {
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    do {
        let index = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 0 : 0
        guard Destination.all.indices.contains(index) else { throw MandelbrotError.invalidView }
        let result = try Renderer.render(view: Destination.all[index].view, width: 1600, height: 1000, samples: 2)!
        try result.encoded(format: url.pathExtension.lowercased() == "png" ? .png : .jpeg).write(to: url, options: .atomic)
        print("Rendered 1600 × 1000 in \(String(format: "%.3f", result.seconds))s: \(url.path)")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
