import AppKit
import SwiftUI

struct DeskMenuBarView: View {
    @ObservedObject var controller: DeskController
    let delegate: AppDelegate

    var body: some View {
        Label {
            Text(controller.isLinked ? controller.deskName : controller.rememberedDesk?.name ?? "Desk Control")
        } icon: {
            Image(nsImage: connectionIndicator)
                .renderingMode(.original)
                .accessibilityLabel(connectionStatus)
        }
        if !controller.isLinked || controller.phase != .ready || controller.isMoving
            || !controller.baseKnown || !controller.hasFreshHeight {
            Text(connectionStatus)
        }
        if controller.baseKnown, let height = controller.heightCM {
            Text("当前高度  \(format(height)) cm")
        }
        Divider()
        if controller.favorites.isEmpty {
            Text("暂无收藏位置")
        } else {
            ForEach(controller.favorites) { favorite in
                Button {
                    controller.move(to: favorite.heightCM, source: .menuBar)
                } label: {
                    Label("\(favorite.name) · \(format(favorite.heightCM)) cm", systemImage: "star")
                }
                .disabled(!controller.canMove(to: favorite.heightCM))
            }
        }
        Divider()
        if !controller.isLinked, let last = controller.rememberedDesk {
            Button("重新连接 \(last.name)") { controller.reconnectLastDesk() }
                .disabled(!controller.bluetoothOn)
        }
        Button("打开主窗口") { delegate.showMainWindow() }
            .keyboardShortcut("o", modifiers: .command)
        Divider()
        Button("退出 Desk Control") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var connectionStatus: String {
        if !controller.bluetoothOn { return controller.bluetoothText }
        if !controller.isLinked { return "未连接" }
        if controller.phase != .ready { return "正在连接…" }
        if controller.isMoving { return controller.status }
        return controller.canMove ? "已连接" : "等待高度数据或校准"
    }

    private var connectionIndicator: NSImage {
        if !controller.isLinked { return DeskConnectionIndicator.disconnected }
        return controller.phase == .ready ? DeskConnectionIndicator.connected : DeskConnectionIndicator.connecting
    }
}

private enum DeskConnectionIndicator {
    static let connected = dot(.systemGreen)
    static let connecting = dot(.systemOrange)
    static let disconnected = dot(.systemGray)

    private static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 16), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 4, width: 8, height: 8)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

enum DeskMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 2, y: 13))
            path.line(to: NSPoint(x: 20, y: 13))
            for x: CGFloat in [6, 16] {
                path.move(to: NSPoint(x: x, y: 13))
                path.line(to: NSPoint(x: x, y: 4))
                path.move(to: NSPoint(x: x - 2.5, y: 4))
                path.line(to: NSPoint(x: x + 2.5, y: 4))
            }
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Desk Control"
        return image
    }()
}
