import AppKit
import SwiftUI

private typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @ObservedObject var controller: DeskController
    var onWindowAttached: ((NSWindow) -> Void)? = nil
    @ViewState private var activeSheet: Panel?
    @ViewState private var sliderValue = 60.0
    @ViewState private var isEditingSlider = false

    private enum Panel: String, Identifiable {
        case favorites, settings
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            mainPane
        }
        .frame(minWidth: 980, minHeight: 600)
        .background(Color.white)
        .foregroundStyle(DeskStyle.ink)
        .tint(DeskStyle.blue)
        .ignoresSafeArea()
        .background(WindowChrome(onEscape: { controller.stop() }, onWindowAttached: onWindowAttached))
        .sheet(item: $activeSheet) { panel in
            switch panel {
            case .favorites:
                FavoritesEditor(controller: controller, onDismiss: { activeSheet = nil })
            case .settings:
                DeskSettingsView(controller: controller, onDismiss: { activeSheet = nil })
            }
        }
        .onAppear { followCurrentHeight() }
        .onChange(of: controller.heightCM) { _ in
            if !isEditingSlider && controller.targetCM == nil { followCurrentHeight() }
        }
        .onChange(of: controller.targetCM) { target in
            if !isEditingSlider {
                if let target { sliderValue = clamp(target) }
                else { followCurrentHeight() }
            }
        }
        .onChange(of: controller.minCM) { _ in sliderValue = clamp(sliderValue) }
        .onChange(of: controller.maxCM) { _ in sliderValue = clamp(sliderValue) }
        .onChange(of: controller.phase) { phase in
            if phase == .idle && activeSheet == .favorites { activeSheet = .settings }
            if phase == .ready && !controller.baseKnown && NSApplication.shared.isActive { open(.settings) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Desk Control")
                .font(.system(size: 18, weight: .semibold))
                .padding(.leading, 90)
                .frame(height: 64)
            HStack {
                Text("收藏位置")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskStyle.secondary)
                Spacer()
                Button("编辑") { open(.favorites) }
                    .font(.system(size: 14, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(controller.canEditFavorites ? DeskStyle.blue : DeskStyle.secondary.opacity(0.45))
                    .disabled(!controller.canEditFavorites)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 14)
            VStack(spacing: 5) {
                ForEach(controller.favorites) { favorite in
                    let selected = (controller.targetCM ?? controller.heightCM)
                        .map { abs($0 - favorite.heightCM) <= 0.15 } ?? false
                    Button {
                        sliderValue = clamp(favorite.heightCM)
                        controller.move(to: favorite.heightCM)
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "star")
                                .font(.system(size: 23, weight: .regular))
                                .foregroundStyle(DeskStyle.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(favorite.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(format(favorite.heightCM)) cm")
                                    .font(.system(size: 13))
                                    .monospacedDigit()
                                    .foregroundStyle(DeskStyle.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 70)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? DeskStyle.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.canMove(to: favorite.heightCM))
                    .accessibilityLabel("前往\(favorite.name)，\(format(favorite.heightCM))厘米")
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 16)
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(DeskStyle.sidebar)
    }

    private var mainPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                Spacer()
                Button { open(.settings) } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(controller.canMove ? DeskStyle.green : controller.isLinked ? Color.orange : DeskStyle.secondary.opacity(0.5))
                            .frame(width: 9, height: 9)
                        Text(connectionTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DeskStyle.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("连接设置")
                Button { open(.settings) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeskStyle.secondary)
                .accessibilityLabel("设置")
            }
            .padding(.trailing, 25)
            .frame(height: 64)
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Text("当前高度")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DeskStyle.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(controller.baseKnown ? controller.heightCM.map(format) ?? "—" : "—")
                            .font(.system(size: 88, weight: .light))
                            .monospacedDigit()
                        Text("cm")
                            .font(.system(size: 25))
                            .foregroundStyle(DeskStyle.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 9) {
                    HStack {
                        Text("所选高度")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DeskStyle.secondary)
                        Spacer()
                        Text("\(format(sliderValue)) cm")
                            .font(.system(size: 19, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(DeskStyle.blue)
                    }
                    HeightSlider(value: $sliderValue,
                                 range: controller.minCM...controller.maxCM,
                                 enabled: controller.canMove && controller.hasTargetControl,
                                 onEditingChanged: { editing in
                                     isEditingSlider = editing
                                     if editing { controller.stop(showStatus: false) }
                                 },
                                 onCommit: { height in
                                     guard NSApplication.shared.isActive, activeSheet == nil else { return }
                                     controller.move(to: height)
                                 })
                        .frame(height: 36)
                    HStack {
                        Text(format(controller.minCM))
                        Spacer()
                        Text(format(controller.maxCM))
                    }
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(DeskStyle.secondary)
                }
                .padding(.top, 42)
                HStack(spacing: 18) {
                    HoldButton(title: "降低", symbol: "arrow.down", enabled: controller.canMove,
                               onPress: { controller.beginJog(up: false) },
                               onRelease: { controller.stop() })
                        .frame(maxWidth: .infinity)
                        .disabled(!controller.canMove)
                    HoldButton(title: "升高", symbol: "arrow.up", enabled: controller.canMove,
                               onPress: { controller.beginJog(up: true) },
                               onRelease: { controller.stop() })
                        .frame(maxWidth: .infinity)
                        .disabled(!controller.canMove)
                }
                .frame(height: 68)
                .padding(.top, 42)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 46)
            .padding(.bottom, 42)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            if let message = errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(DeskStyle.control, in: RoundedRectangle(cornerRadius: 7))
                    .padding(18)
                    .accessibilityLabel(message)
            }
        }
    }

    private var connectionTitle: String {
        guard controller.isLinked else { return "连接桌子" }
        let state: String
        if controller.phase == .connecting { state = "连接中" }
        else if controller.phase != .ready { state = "初始化中" }
        else if controller.isMoving { state = controller.status }
        else { state = "已连接" }
        return "\(controller.deskName) · \(state)"
    }

    private var errorMessage: String? {
        let markers = ["失败", "故障", "中断", "超时", "无效", "超出", "请先", "须在", "未继续"]
        return markers.contains { controller.status.contains($0) } ? controller.status : nil
    }

    private func open(_ panel: Panel) {
        controller.stop(showStatus: false)
        activeSheet = panel
    }

    private func clamp(_ value: Double) -> Double {
        Swift.min(controller.maxCM, Swift.max(controller.minCM, value))
    }

    private func followCurrentHeight() {
        if let height = controller.heightCM, controller.baseKnown { sliderValue = clamp(height) }
        else { sliderValue = clamp(sliderValue) }
    }
}
