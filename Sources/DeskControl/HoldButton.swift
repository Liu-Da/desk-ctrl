import AppKit
import SwiftUI

/// Nonblocking mouse tracking lets BLE timers run normally while the button is held.
struct HoldButton: NSViewRepresentable {
    let title: String
    let symbol: String
    let enabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeNSView(context: Context) -> PressButton {
        let button = PressButton()
        button.isBordered = false
        button.focusRingType = .none
        button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: 20, weight: .medium)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.setAccessibilityLabel("按住\(title)，松开停止")
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: PressButton, context: Context) {
        button.title = title
        let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            .applying(.init(paletteColors: [NSColor(DeskStyle.blue)]))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(configuration)
        button.isEnabled = enabled
        button.setAccessibilityEnabled(enabled)
        button.onPress = onPress
        button.onRelease = onRelease
        if !enabled { button.endPress() }
    }

    static func dismantleNSView(_ button: PressButton, coordinator: ()) { button.endPress() }
}

final class PressButton: NSButton {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var pressed = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor(pressed ? DeskStyle.selection : DeskStyle.selection.opacity(isEnabled ? 0.76 : 0.35)).setFill()
        path.fill()

        let label = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor(DeskStyle.ink).withAlphaComponent(isEnabled ? 1 : 0.4)
        ])
        let size = label.size()
        let symbolSize: CGFloat = 24
        let spacing: CGFloat = 14
        let left = (bounds.width - symbolSize - spacing - size.width) / 2
        image?.draw(in: NSRect(x: left, y: (bounds.height - symbolSize) / 2,
                              width: symbolSize, height: symbolSize),
                    from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4,
                    respectFlipped: true, hints: nil)
        label.draw(at: NSPoint(x: left + symbolSize + spacing, y: (bounds.height - size.height) / 2))
        if window?.firstResponder === self {
            NSColor(DeskStyle.blue).withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        startPress()
    }

    override func mouseDragged(with event: NSEvent) {
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { endPress() }
    }

    override func mouseUp(with event: NSEvent) { endPress() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 && !event.isARepeat && isEnabled { startPress() }
        else if event.keyCode == 53 { endPress() }
        else { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { endPress() }
        else { super.keyUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        endPress()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private func startPress() {
        guard !pressed else { return }
        pressed = true
        needsDisplay = true
        onPress?()
    }

    func endPress() {
        guard pressed else { return }
        pressed = false
        needsDisplay = true
        onRelease?()
    }
}
