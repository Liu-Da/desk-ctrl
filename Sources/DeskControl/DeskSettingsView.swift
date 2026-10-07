import SwiftUI

private typealias SettingsState<Value> = SwiftUI.State<Value>

struct DeskSettingsView: View {
    @ObservedObject var controller: DeskController
    let onDismiss: () -> Void
    @SettingsState private var calibrationText = ""
    @SettingsState private var minText = ""
    @SettingsState private var maxText = ""
    @SettingsState private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .frame(height: 64)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connection
                    Divider()
                    calibration
                    Text(controller.status)
                        .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 660, height: 550)
        .foregroundStyle(DeskStyle.ink)
        .background(Color.white)
        .tint(DeskStyle.blue)
        .onAppear {
            minText = format(controller.minCM)
            maxText = format(controller.maxCM)
            if controller.baseKnown { calibrationText = controller.heightCM.map(format) ?? "" }
        }
        .onChange(of: controller.minCM) { minText = format($0) }
        .onChange(of: controller.maxCM) { maxText = format($0) }
        .onChange(of: controller.heightCM) { value in
            if calibrationText.isEmpty && controller.baseKnown { calibrationText = value.map(format) ?? "" }
        }
    }

    private var calibration: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("高度校准与范围").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 12) {
                Text("面板高度").frame(width: 76, alignment: .leading)
                TextField("当前高度", text: $calibrationText).deskField().frame(width: 120)
                Text("cm").foregroundStyle(DeskStyle.secondary)
                Spacer()
                Button("校准") {
                    if let value = deskNumber(calibrationText) { controller.calibrate(actualCM: value) }
                }
                .buttonStyle(FlatButtonStyle())
                .disabled(!controller.hasFreshHeight || controller.isMoving || deskNumber(calibrationText) == nil)
            }
            HStack(spacing: 12) {
                Text("升降范围").frame(width: 76, alignment: .leading)
                TextField("最低", text: $minText).deskField().frame(width: 95)
                Text("–").foregroundStyle(DeskStyle.secondary)
                TextField("最高", text: $maxText).deskField().frame(width: 95)
                Text("cm").foregroundStyle(DeskStyle.secondary)
                Spacer()
                Button("保存范围") {
                    if let min = deskNumber(minText), let max = deskNumber(maxText) {
                        controller.saveLimits(min: min, max: max)
                    }
                }
                .buttonStyle(FlatButtonStyle())
                .disabled(!controller.isLinked || controller.isMoving || deskNumber(minText) == nil || deskNumber(maxText) == nil)
            }
            Text(controller.baseKnown ? "基础高度：\(controller.baseSource)" : "请填入桌子面板显示的当前高度后校准")
                .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
        }
        .font(.system(size: 13))
    }

    private var footer: some View {
        HStack {
            Button(copied ? "已复制" : "复制诊断") {
                controller.copyDiagnostics()
                copied = true
            }
            .buttonStyle(FlatButtonStyle())
            Spacer()
            Button("完成", action: onDismiss)
                .buttonStyle(FlatButtonStyle(kind: .primary))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    @ViewBuilder private var connection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("蓝牙连接").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(controller.bluetoothText).font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
                if !controller.isLinked {
                    Button(controller.isScanning ? "重新扫描" : "扫描桌子") { controller.scan() }
                        .buttonStyle(FlatButtonStyle())
                        .disabled(!controller.bluetoothOn)
                }
            }
            if controller.isLinked {
                HStack {
                    Circle().fill(controller.canMove ? DeskStyle.green : Color.orange).frame(width: 8, height: 8)
                    Text(controller.deskName).font(.system(size: 14, weight: .medium))
                    if controller.phase != .ready { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("断开连接") { controller.disconnect() }.buttonStyle(FlatButtonStyle())
                }
                .frame(height: 70)
            } else {
                Text("长按桌子面板的蓝牙键 2 秒，再选择相同 DESK 编号")
                    .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(controller.desks) { desk in
                            HStack {
                                Text(desk.name).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Button("连接") { controller.connect(desk) }.buttonStyle(FlatButtonStyle())
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(DeskStyle.sidebar, in: RoundedRectangle(cornerRadius: 7))
                        }
                        if controller.desks.isEmpty {
                            HStack(spacing: 10) {
                                if controller.isScanning { ProgressView().controlSize(.small) }
                                Text(controller.isScanning ? "正在寻找桌子…" : "未发现桌子")
                                    .font(.system(size: 13)).foregroundStyle(DeskStyle.secondary)
                                Spacer()
                            }
                            .padding(.top, 12)
                        }
                    }
                }
                .frame(height: 110)
            }
        }
    }
}
