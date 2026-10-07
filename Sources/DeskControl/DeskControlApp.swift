import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DeskController(diagnosticsPath: diagnosticsArgument())
    weak var mainWindow: NSWindow?
    var createMainWindow: (() -> Void)?
    private var windowObservers: [NSObjectProtocol] = []
    private var sleepObserver: NSObjectProtocol?
    private var terminationPending = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start after AppKit has registered the application and menu bar scene.
        controller.startBluetooth()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.controller.stop(showStatus: false) }
    }

    func applicationDidResignActive(_ notification: Notification) {
        controller.stopForMainWindowFocusLoss()
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        mainWindow = window
        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in self?.controller.stopForMainWindowFocusLoss() })
        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.controller.stopForMainWindowFocusLoss()
            NSApplication.shared.setActivationPolicy(.accessory)
        })
    }

    func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        createMainWindow?()
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.mainWindow else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            if window.isVisible { window.makeKeyAndOrderFront(nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        controller.prepareToQuit()
        // Leave a short interval for CoreBluetooth to deliver the stop packet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    deinit {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }
}

@main
struct DeskControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var controller: DeskController { delegate.controller }

    var body: some Scene {
        Window("Desk Control", id: DeskMainWindow.sceneID) {
            DeskMainWindow(controller: controller, delegate: delegate)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("桌子") {
                Button("停止升降") { controller.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
        MenuBarExtra {
            DeskMenuBarView(controller: controller, delegate: delegate)
        } label: {
            Image(nsImage: DeskMenuBarIcon.image)
                .accessibilityLabel("Desk Control")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct DeskMainWindow: View {
    static let sceneID = "desk-main"
    @ObservedObject var controller: DeskController
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(controller: controller, onWindowAttached: delegate.registerMainWindow)
            .onAppear {
                let action = openWindow
                delegate.createMainWindow = { action(id: Self.sceneID) }
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .preferredColorScheme(.light)
    }
}

private func diagnosticsArgument() -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--diagnostics"), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
