import AppKit
import SwiftUI

struct WindowChrome: NSViewRepresentable {
    let onEscape: () -> Void
    var onWindowAttached: ((NSWindow) -> Void)? = nil

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView()
        view.onEscape = onEscape
        view.onWindowAttached = onWindowAttached
        return view
    }

    func updateNSView(_ view: WindowChromeView, context: Context) {
        view.onEscape = onEscape
        view.onWindowAttached = onWindowAttached
    }
}

final class WindowChromeView: NSView {
    var onEscape: (() -> Void)?
    var onWindowAttached: ((NSWindow) -> Void)?
    private var keyMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .white
        window.isMovableByWindowBackground = true
        window.toolbar = nil
        window.contentMinSize = NSSize(width: 980, height: 600)
        if UserDefaults.standard.integer(forKey: "flatWindowLayoutVersion") < 1 {
            window.setContentSize(NSSize(width: 1080, height: 640))
            window.center()
            UserDefaults.standard.set(1, forKey: "flatWindowLayoutVersion")
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && event.window === self?.window { self?.onEscape?() }
            return event
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didUpdateNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didEndSheetNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name,
                                                                          object: window, queue: .main) { [weak self] _ in
                self?.alignTrafficLights()
            })
        }
        DispatchQueue.main.async { [weak self] in self?.alignTrafficLights() }
        onWindowAttached?(window)
    }

    private func alignTrafficLights() {
        guard let window, let content = window.contentView else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        // The native titlebar otherwise clips buttons moved into our 64-point header.
        if let titlebar = window.standardWindowButton(.closeButton)?.superview,
           let container = titlebar.superview {
            let top = container.frame.maxY
            if container.frame.height != 64 {
                container.setFrameSize(NSSize(width: container.frame.width, height: 64))
                container.setFrameOrigin(NSPoint(x: container.frame.minX, y: top - 64))
            }
            if titlebar.frame.height != 64 { titlebar.setFrameSize(NSSize(width: titlebar.frame.width, height: 64)) }
        }
        let y: CGFloat = content.isFlipped ? 32 : content.bounds.height - 32
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
            let point = parent.convert(NSPoint(x: 20 + CGFloat(index) * 20, y: y), from: content)
            let origin = NSPoint(x: point.x, y: point.y - button.frame.height / 2)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    private func removeObservers() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        keyMonitor = nil
        windowObservers = []
    }

    deinit { removeObservers() }
}
