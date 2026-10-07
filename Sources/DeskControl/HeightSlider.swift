import AppKit
import SwiftUI

/// Changes the selection while dragging, and commits a target only on release.
struct HeightSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let enabled: Bool
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void

    func makeNSView(context: Context) -> HeightSliderView {
        let view = HeightSliderView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.slider)
        view.setAccessibilityLabel("所选高度，厘米")
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: HeightSliderView, context: Context) {
        view.onValueChanged = { value = $0 }
        view.onEditingChanged = onEditingChanged
        view.onCommit = onCommit
        if view.range != range { view.cancelEditing(); view.range = range }
        view.isEnabled = enabled
        if !enabled { view.cancelEditing() }
        if !view.isEditing { view.value = view.clamp(value) }
        view.setAccessibilityEnabled(enabled)
        view.setAccessibilityMinValue(range.lowerBound)
        view.setAccessibilityMaxValue(range.upperBound)
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: HeightSliderView, coordinator: ()) { view.cancelEditing() }
}

final class HeightSliderView: NSView {
    var range: ClosedRange<Double> = 60...130
    var value = 60.0
    var isEnabled = true
    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onCommit: ((Double) -> Void)?
    private(set) var isEditing = false
    private var startingValue = 60.0
    private var editingKey: UInt16?
    private var focusObservers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { isEnabled }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 36) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        focusObservers = []
        cancelEditing()
        guard let window else { return }
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                               (NSApplication.didResignActiveNotification, NSApplication.shared as AnyObject)] {
            focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: object,
                                                                         queue: .main) { [weak self] _ in
                self?.cancelEditing()
            })
        }
    }

    deinit {
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func clamp(_ value: Double) -> Double { Swift.min(range.upperBound, Swift.max(range.lowerBound, value)) }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 14
        let width = Swift.max(1, bounds.width - inset * 2)
        let fraction = (clamp(value) - range.lowerBound) / (range.upperBound - range.lowerBound)
        let center = bounds.midY
        let track = NSRect(x: inset, y: center - 4, width: width, height: 8)
        NSColor(DeskStyle.border).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        let progress = NSRect(x: inset, y: center - 4, width: width * fraction, height: 8)
        NSColor(DeskStyle.blue).withAlphaComponent(isEnabled ? 1 : 0.35).setFill()
        NSBezierPath(roundedRect: progress, xRadius: 4, yRadius: 4).fill()
        let knob = NSBezierPath(ovalIn: NSRect(x: inset + width * fraction - 12.5,
                                              y: center - 12.5, width: 25, height: 25))
        NSColor.white.setFill()
        knob.fill()
        NSColor(isEnabled ? DeskStyle.blue : DeskStyle.border).setStroke()
        knob.lineWidth = 1.5
        knob.stroke()
        if window?.firstResponder === self && isEnabled {
            NSColor(DeskStyle.blue).withAlphaComponent(0.12).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: inset + width * fraction - 16.5,
                                                  y: center - 16.5, width: 33, height: 33))
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        beginEditing()
        updateValue(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing, isEnabled else { return }
        updateValue(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        guard isEnabled else { cancelEditing(); return }
        updateValue(at: convert(event.locationInWindow, from: nil))
        finishEditing(commit: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelEditing(); return }
        guard isEnabled, [UInt16(123), 124, 125, 126, 115, 119].contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        if !isEditing { beginEditing(); editingKey = event.keyCode }
        guard editingKey == event.keyCode else { return }
        let step = event.modifierFlags.contains(.shift) ? 1.0 : 0.1
        switch event.keyCode {
        case 123, 125: setValue(value - step)
        case 124, 126: setValue(value + step)
        case 115: setValue(range.lowerBound)
        case 119: setValue(range.upperBound)
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == editingKey { finishEditing(commit: true) }
        else { super.keyUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        cancelEditing()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func accessibilityValue() -> Any? { value }

    override func accessibilityPerformIncrement() -> Bool { accessibilityStep(0.1) }
    override func accessibilityPerformDecrement() -> Bool { accessibilityStep(-0.1) }

    private func accessibilityStep(_ step: Double) -> Bool {
        guard isEnabled, !isEditing else { return false }
        beginEditing()
        setValue(value + step)
        finishEditing(commit: true)
        return true
    }

    private func beginEditing() {
        guard !isEditing else { return }
        startingValue = value
        isEditing = true
        onEditingChanged?(true)
    }

    private func updateValue(at point: NSPoint) {
        let width = Swift.max(1, bounds.width - 28)
        let fraction = Swift.min(1, Swift.max(0, (point.x - 14) / width))
        setValue(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func setValue(_ newValue: Double) {
        value = clamp((newValue * 10).rounded() / 10)
        onValueChanged?(value)
        needsDisplay = true
    }

    private func finishEditing(commit: Bool) {
        guard isEditing else { return }
        let changed = abs(value - startingValue) >= 0.05
        isEditing = false
        editingKey = nil
        onEditingChanged?(false)
        if commit && changed { onCommit?(value) }
    }

    func cancelEditing() {
        guard isEditing else { return }
        setValue(startingValue)
        finishEditing(commit: false)
    }
}
