import AppKit
import Combine
import CoreBluetooth
import DeskCore
import Foundation

struct NearbyDesk: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    let peripheral: CBPeripheral
}

final class DeskController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Phase: String { case idle, connecting, discovering, initialising, ready }
    enum MotionSource { case mainWindow, menuBar }
    private enum DPGStep { case base, user, enableUser(Data) }

    @Published var desks: [NearbyDesk] = []
    @Published var isScanning = false
    @Published var bluetoothText = "正在准备蓝牙…"
    @Published var phase: Phase = .idle
    @Published var status = "请将桌子切换到蓝牙配对模式"
    @Published var deskName = "未连接桌子"
    @Published var heightCM: Double?
    @Published var isMoving = false
    @Published var hasFreshHeight = false
    @Published var baseKnown = false
    @Published var baseSource = "等待读取"
    @Published var minCM = 60.0
    @Published var maxCM = 130.0
    @Published var favorites: [DeskFavorite] = []
    @Published var targetCM: Double?
    @Published var logs: [String] = []
    @Published private(set) var rememberedDesk: RememberedDesk?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var remainingServices: Set<CBUUID> = []
    private var scanTimer: Timer?
    private var connectTimer: Timer?
    private var pollTimer: Timer?
    private var motionTimer: Timer?
    private var dpgTimer: Timer?
    private var diagnosticTimer: Timer?
    private var dpgStep: DPGStep?
    private var userReady = false
    private var baseMM = 620.0
    private var telemetry: LinakProtocol.Telemetry?
    private var telemetryAt = 0.0
    private var heightReadPending = false
    private var motion: MotionGuard?
    private var motionSource: MotionSource?
    private var pendingStop = false
    private var busyWrites: Set<String> = []
    private var cooldownUntil = 0.0
    private let defaults = UserDefaults.standard
    private let connectionStore = DeskConnectionStore()
    private var automaticReconnect: DeskReconnectAttempt?
    private var pendingCancellations: Set<UUID> = []
    private var automaticReconnectSuppressed = false
    private var isQuitting = false
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private let diagnosticsPath: String?

    var bluetoothOn: Bool { central?.state == .poweredOn }
    var isLinked: Bool { peripheral != nil }
    var canMove: Bool {
        phase == .ready && userReady && baseKnown && hasFreshHeight
            && now - telemetryAt <= 2 && now >= cooldownUntil
            && heightCM.map { (40...150).contains($0) } == true
    }
    var hasTargetControl: Bool { characteristics[LinakProtocol.target] != nil }
    var deskID: UUID? { peripheral?.identifier }
    var canEditFavorites: Bool { deskID != nil && phase == .ready }

    func canMove(to height: Double) -> Bool {
        canMove && hasTargetControl && MotionGuard.validTarget(height, min: minCM, max: maxCM, baseMM: baseMM)
    }

    init(diagnosticsPath: String? = nil) {
        self.diagnosticsPath = diagnosticsPath
        rememberedDesk = connectionStore.load()
        super.init()
    }

    func startBluetooth() {
        guard central == nil, !isQuitting else { return }
        central = CBCentralManager(delegate: self, queue: .main)
        if diagnosticsPath != nil {
            diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.writeDiagnostics()
            }
        }
    }

    func scan() {
        guard bluetoothOn, !isLinked else { return }
        cancelAutomaticReconnect()
        automaticReconnectSuppressed = true
        startScan()
    }

    private func startScan() {
        guard bluetoothOn, !isLinked, !isQuitting else { return }
        scanTimer?.invalidate()
        desks = []
        isScanning = true
        if let attempt = automaticReconnect {
            status = "正在寻找上次的 \(attempt.desk.name)…"
        } else {
            status = "正在寻找附近的 LINAK 桌子…"
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("开始扫描（仅扫描，不发送升降指令）")
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self else { return }
            let reconnectName = self.automaticReconnect?.desk.name
            self.stopScan()
            self.cancelAutomaticReconnect()
            if let reconnectName {
                self.status = "暂时未找到 \(reconnectName)，可在菜单栏重新连接，或进入设置扫描"
            } else {
                self.status = self.desks.isEmpty ? "未找到桌子。长按桌子蓝牙键 2 秒后，再点重新扫描。" : "选择与桌子屏幕编号一致的设备"
            }
        }
    }

    func reconnectLastDesk() {
        guard bluetoothOn, !isLinked, !isQuitting, let rememberedDesk else { return }
        automaticReconnectSuppressed = false
        stopScan()
        let cached = central.retrievePeripherals(withIdentifiers: [rememberedDesk.id]).first
        automaticReconnect = DeskReconnectAttempt(desk: rememberedDesk, hasCachedPeripheral: cached != nil)
        if let cached {
            startConnection(NearbyDesk(id: cached.identifier, name: rememberedDesk.name,
                                      rssi: 0, peripheral: cached), automatic: true)
        } else {
            startScan()
        }
    }

    private func cancelAutomaticReconnect() {
        automaticReconnect?.cancel()
        automaticReconnect = nil
    }

    private func stopScan() {
        central?.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        isScanning = false
    }

    func connect(_ desk: NearbyDesk) {
        guard bluetoothOn, !isLinked else { return }
        cancelAutomaticReconnect()
        automaticReconnectSuppressed = false
        startConnection(desk, automatic: false)
    }

    private func startConnection(_ desk: NearbyDesk, automatic: Bool) {
        guard bluetoothOn, !isLinked, !isQuitting else { return }
        stopScan()
        clearLink()
        peripheral = desk.peripheral
        deskName = desk.name
        peripheral?.delegate = self
        loadPreferences()
        phase = .connecting
        status = automatic ? "正在自动重连 \(desk.name)…" : "正在连接 \(desk.name)…"
        log(status)
        // CoreBluetooth can reuse a peripheral object. Let a previous cancellation
        // finish before starting a new connection to the same device.
        if !pendingCancellations.contains(desk.id) { central.connect(desk.peripheral) }
        connectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.failConnection("连接超时，请重新进入配对模式；若手机已连接，请先断开手机。")
        }
    }

    func disconnect() {
        automaticReconnectSuppressed = true
        cancelAutomaticReconnect()
        stop()
        let old = peripheral
        clearLink()
        peripheral = nil
        phase = .idle
        deskName = "未连接桌子"
        status = "已断开连接"
        if let old { cancelConnection(old) }
        log(status)
    }

    func beginJog(up: Bool) {
        beginMotion(up ? .up : .down)
    }

    func move(to height: Double, source: MotionSource = .mainWindow) {
        guard MotionGuard.validTarget(height, min: minCM, max: maxCM, baseMM: baseMM) else {
            status = "目标高度须在 \(format(minCM))–\(format(maxCM)) cm 内，且不低于桌子基础高度"
            return
        }
        guard hasTargetControl else { status = "这台控制器没有提供目标高度接口，请使用按住升降"; return }
        beginMotion(.target(height), source: source)
    }

    private func beginMotion(_ mode: MotionGuard.Mode, source: MotionSource = .mainWindow) {
        guard canMove, let height = heightCM else {
            status = baseKnown ? "请先连接桌子并等待有效的高度数据" : "请先完成高度校准"
            return
        }
        stop(showStatus: false)
        motion = MotionGuard(mode: mode, heightCM: height, now: now)
        motionSource = source
        isMoving = true
        switch mode {
        case .up: targetCM = nil; status = "正在升高"
        case .down: targetCM = nil; status = "正在降低"
        case .target(let target): targetCM = target; status = "正在前往 \(format(target)) cm"
        }
        send(LinakProtocol.Command.wake.data, to: LinakProtocol.control)
        log(status)
        tickMotion()
        if motion != nil {
            motionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.tickMotion()
            }
            // Keep the heartbeat alive while an AppKit button tracks the mouse.
            if let motionTimer { RunLoop.main.add(motionTimer, forMode: .common) }
        }
    }

    private func tickMotion() {
        guard var session = motion else { return }
        guard peripheral?.state == .connected, let height = heightCM else {
            stop(reason: "蓝牙连接中断")
            return
        }
        let decision = session.evaluate(heightCM: height, telemetryAt: telemetryAt, now: now, min: minCM, max: maxCM)
        motion = session
        switch decision {
        case .arrived: stop(reason: "已到达目标高度")
        case .stop(let message): stop(reason: message)
        case .keepMoving:
            if pendingStop { return }
            switch session.mode {
            case .up: send(LinakProtocol.Command.up.data, to: LinakProtocol.control)
            case .down: send(LinakProtocol.Command.down.data, to: LinakProtocol.control)
            case .target(let target):
                if let data = LinakProtocol.encodeTarget(heightCM: target, baseMM: baseMM) {
                    send(data, to: LinakProtocol.target)
                } else { stop(reason: "目标高度无法编码") }
            }
            readHeight()
        }
    }

    func stop(showStatus: Bool = true, reason: String? = nil) {
        let wasMoving = motion != nil
        motion = nil
        motionSource = nil
        motionTimer?.invalidate()
        motionTimer = nil
        isMoving = false
        targetCM = nil
        if peripheral?.state == .connected, characteristics[LinakProtocol.control] != nil {
            pendingStop = true
            flushStop()
        }
        if let reason { status = reason; log(reason) }
        else if wasMoving && showStatus { status = "已发送停止指令"; log(status) }
    }

    func stopForMainWindowFocusLoss() {
        guard motionSource == .mainWindow, isMoving else { return }
        stop(reason: "窗口失去焦点，已停止")
    }

    private func flushStop() {
        guard pendingStop else { return }
        if send(LinakProtocol.Command.stop.data, to: LinakProtocol.control, urgent: true) {
            pendingStop = false
        }
    }

    @discardableResult
    private func send(_ data: Data, to uuid: String, urgent: Bool = false) -> Bool {
        guard let peripheral, peripheral.state == .connected, let char = characteristics[uuid] else { return false }
        if char.properties.contains(.writeWithoutResponse) {
            guard peripheral.canSendWriteWithoutResponse else { return false }
            peripheral.writeValue(data, for: char, type: .withoutResponse)
        } else if char.properties.contains(.write) {
            // At most one ordinary command is in flight per characteristic.
            // A stop can be queued immediately behind it.
            guard urgent || !busyWrites.contains(uuid) else { return false }
            busyWrites.insert(uuid)
            peripheral.writeValue(data, for: char, type: .withResponse)
        } else { return false }
        return true
    }

    private func readHeight() {
        guard !heightReadPending, let peripheral, peripheral.state == .connected,
              let char = characteristics[LinakProtocol.height], char.properties.contains(.read) else { return }
        heightReadPending = true
        peripheral.readValue(for: char)
    }

    @discardableResult
    func saveFavorites(_ newFavorites: [DeskFavorite], for expectedDeskID: UUID) -> Bool {
        guard canEditFavorites, !isMoving, deskID == expectedDeskID else {
            status = "请连接原来的桌子后再保存收藏"
            return false
        }
        do {
            let store = FavoriteStore(defaults: defaults)
            try store.save(newFavorites, for: expectedDeskID)
            favorites = store.load(for: expectedDeskID)
            status = "已保存收藏位置"
            log(status)
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    func calibrate(actualCM: Double) {
        guard !isMoving, hasFreshHeight, let telemetry, actualCM.isFinite, (40...150).contains(actualCM) else {
            status = "连接后，输入桌子面板显示的当前高度（40–150 cm）"
            return
        }
        let offset = actualCM * 10 - Double(telemetry.travel) / 10
        guard (100...1500).contains(offset) else { status = "校准值与桌子数据不符，请核对"; return }
        baseMM = offset
        baseKnown = true
        baseSource = "手动校准"
        heightCM = telemetry.heightCM(baseMM: baseMM)
        setPreference(offset, "baseMM")
        status = "已校准为 \(format(actualCM)) cm"
        log(status)
    }

    func saveLimits(min: Double, max: Double) {
        guard !isMoving, MotionGuard.validLimits(min: min, max: max) else {
            status = "范围须在 40–150 cm 内，最高高度须比最低高度至少高 1 cm"
            return
        }
        minCM = min
        maxCM = max
        setPreference(min, "minCM")
        setPreference(max, "maxCM")
        status = "已保存升降范围 \(format(min))–\(format(max)) cm"
    }

    private func preferenceKey(_ name: String) -> String? {
        peripheral.map { "desk.\($0.identifier.uuidString).\(name)" }
    }
    private func setPreference(_ value: Double, _ name: String) {
        if let key = preferenceKey(name) { defaults.set(value, forKey: key) }
    }
    private func preference(_ name: String) -> Double? {
        guard let key = preferenceKey(name), let value = defaults.object(forKey: key) as? NSNumber else { return nil }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }
    private func loadPreferences() {
        minCM = preference("minCM") ?? 60
        maxCM = preference("maxCM") ?? 130
        if !MotionGuard.validLimits(min: minCM, max: maxCM) { minCM = 60; maxCM = 130 }
        if let deskID { favorites = FavoriteStore(defaults: defaults).load(for: deskID) }
        if let base = preference("baseMM"), (100...1500).contains(base) {
            baseMM = base; baseKnown = true; baseSource = "手动校准"
        }
    }

    private func clearLink() {
        connectTimer?.invalidate(); connectTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        motionTimer?.invalidate(); motionTimer = nil
        dpgTimer?.invalidate(); dpgTimer = nil
        motion = nil
        motionSource = nil
        isMoving = false
        characteristics = [:]
        remainingServices = []
        dpgStep = nil
        userReady = false
        pendingStop = false
        busyWrites = []
        heightReadPending = false
        telemetry = nil
        heightCM = nil
        hasFreshHeight = false
        baseKnown = false
        baseSource = "等待读取"
        baseMM = 620
        favorites = []
        targetCM = nil
        cooldownUntil = 0
    }

    private func failConnection(_ message: String, allowReconnectFallback: Bool = true) {
        let searchForRememberedDesk = allowReconnectFallback
            && automaticReconnect?.connectionFailed() == true
        let old = peripheral
        stop(showStatus: false)
        clearLink()
        peripheral = nil
        phase = .idle
        deskName = "未连接桌子"
        status = message
        log(message)
        if let old { cancelConnection(old) }
        if searchForRememberedDesk, bluetoothOn, !automaticReconnectSuppressed, !isQuitting {
            startScan()
        } else {
            cancelAutomaticReconnect()
        }
    }

    private func cancelConnection(_ peripheral: CBPeripheral) {
        guard peripheral.state != .disconnected else { return }
        pendingCancellations.insert(peripheral.identifier)
        central.cancelPeripheralConnection(peripheral)
    }

    private func finishCancellation(_ peripheral: CBPeripheral) -> Bool {
        guard pendingCancellations.remove(peripheral.identifier) != nil else { return false }
        if let current = self.peripheral, current.identifier == peripheral.identifier,
           phase == .connecting, bluetoothOn, !isQuitting {
            central.connect(current)
        }
        return true
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothText = "蓝牙已开启"
            if !isLinked && !isQuitting {
                if rememberedDesk != nil && !automaticReconnectSuppressed { reconnectLastDesk() }
                else { startScan() }
            }
        case .poweredOff: bluetoothText = "蓝牙未开启"
        case .unauthorized: bluetoothText = "请允许 Desk Control 使用蓝牙"
        case .unsupported: bluetoothText = "这台 Mac 不支持低功耗蓝牙"
        case .resetting: bluetoothText = "蓝牙正在重启"
        case .unknown: bluetoothText = "正在准备蓝牙…"
        @unknown default: bluetoothText = "蓝牙暂不可用"
        }
        if central.state != .poweredOn {
            if isLinked { failConnection(bluetoothText, allowReconnectFallback: false) }
            pendingCancellations = []
            cancelAutomaticReconnect()
            stopScan()
        }
        log(bluetoothText)
        writeDiagnostics()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning, !isLinked, !isQuitting else { return }
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard LinakProtocol.isDesk(name: advertisedName, serviceUUIDs: services.map(\.uuidString)) else { return }
        let name = advertisedName ?? "LINAK · \(peripheral.identifier.uuidString.suffix(6))"
        let desk = NearbyDesk(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        if let index = desks.firstIndex(where: { $0.id == desk.id }) { desks[index] = desk }
        else { desks.append(desk); log("发现 \(name)") }
        desks.sort { $0.rssi > $1.rssi }
        if automaticReconnect?.discovered(desk.id) == true {
            startConnection(desk, automatic: true)
        } else if automaticReconnect == nil {
            status = "选择与桌子屏幕编号一致的设备"
        }
        writeDiagnostics()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral, !pendingCancellations.contains(peripheral.identifier) else { return }
        phase = .discovering
        status = "正在读取桌子接口…"
        peripheral.discoverServices(LinakProtocol.services.map(CBUUID.init(string:)))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if finishCancellation(peripheral) { return }
        guard self.peripheral === peripheral else { return }
        failConnection("连接失败：\(error?.localizedDescription ?? "请重新进入配对模式")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if finishCancellation(peripheral) { return }
        guard self.peripheral === peripheral else { return }
        failConnection("连接已断开\(error.map { "：" + $0.localizedDescription } ?? "")，请重新连接")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            failConnection("读取接口失败：\(error?.localizedDescription ?? "未找到 LINAK 服务")")
            return
        }
        remainingServices = Set(services.map(\.uuid))
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if let error { failConnection("读取控制接口失败：\(error.localizedDescription)"); return }
        for char in service.characteristics ?? [] {
            characteristics[char.uuid.uuidString.lowercased()] = char
        }
        remainingServices.remove(service.uuid)
        guard remainingServices.isEmpty else { return }
        guard let control = characteristics[LinakProtocol.control],
              control.properties.contains(.write) || control.properties.contains(.writeWithoutResponse),
              let height = characteristics[LinakProtocol.height], height.properties.contains(.read) else {
            failConnection("该设备没有提供兼容的 LINAK 控制和高度接口")
            return
        }
        phase = .initialising
        status = "正在读取高度并初始化控制器…"
        if height.properties.contains(.notify) { peripheral.setNotifyValue(true, for: height) }
        if let errorChar = characteristics[LinakProtocol.error], errorChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: errorChar)
        }
        readHeight()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.hasFreshHeight = self.telemetry != nil && self.now - self.telemetryAt <= 2
            self.readHeight()
        }
        if let pollTimer { RunLoop.main.add(pollTimer, forMode: .common) }
        if let dpg = characteristics[LinakProtocol.dpg] {
            if dpg.properties.contains(.notify) { peripheral.setNotifyValue(true, for: dpg) }
            else { runDPG(.base) }
        } else {
            userReady = true
            finishInitialisation()
        }
        log("已读取服务：\(characteristics.keys.sorted().joined(separator: ", "))")
    }

    private func runDPG(_ step: DPGStep) {
        guard let char = characteristics[LinakProtocol.dpg] else { return }
        dpgTimer?.invalidate()
        dpgStep = step
        let data: Data
        switch step {
        case .base: data = LinakProtocol.readDPG(0x81)
        case .user: data = LinakProtocol.readDPG(0x86)
        case .enableUser(let payload): data = LinakProtocol.writeDPG(0x86, payload: payload)
        }
        guard send(data, to: LinakProtocol.dpg) else { dpgTimedOut(); return }
        if !char.isNotifying, char.properties.contains(.read) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.dpgStep != nil, self.characteristics[LinakProtocol.dpg] === char else { return }
                self.peripheral?.readValue(for: char)
            }
        }
        dpgTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.dpgTimedOut() }
    }

    private func dpgTimedOut() {
        guard let step = dpgStep else { return }
        dpgTimer?.invalidate(); dpgTimer = nil
        dpgStep = nil
        switch step {
        case .base: log("未读到基础高度，需要手动校准"); runDPG(.user)
        case .user, .enableUser:
            userReady = false
            log("控制器用户初始化失败")
            finishInitialisation()
        }
    }

    private func receivedDPG(_ data: Data) {
        guard let step = dpgStep else { return }
        switch step {
        case .base:
            guard let base = LinakProtocol.decodeBaseMM(data) else { return }
            if preference("baseMM") == nil {
                baseMM = base; baseKnown = true; baseSource = "从桌子读取"
                heightCM = telemetry?.heightCM(baseMM: baseMM)
            }
            log("基础高度 \(format(base / 10)) cm")
            dpgTimer?.invalidate(); dpgStep = nil
            runDPG(.user)
        case .user:
            guard var payload = LinakProtocol.dpgPayload(data), !payload.isEmpty else { return }
            dpgTimer?.invalidate(); dpgStep = nil
            if payload[0] == 1 { userReady = true; finishInitialisation() }
            else {
                // DPG1C requires an active user. Preserve the rest of its user identifier.
                payload[0] = 1
                runDPG(.enableUser(payload))
            }
        case .enableUser:
            guard data == Data([1, 0]) else { return }
            dpgTimer?.invalidate(); dpgStep = nil
            userReady = true
            log("已启用 DPG1C 蓝牙控制用户")
            finishInitialisation()
        }
    }

    private func finishInitialisation() {
        connectTimer?.invalidate(); connectTimer = nil
        phase = .ready
        if !userReady { status = "控制器初始化未完成，请断开后重新连接" }
        else if !baseKnown { status = "已连接。请在设置里用桌子面板高度完成校准。" }
        else { status = "已连接 · 等待你的升降操作" }
        if userReady { rememberCurrentDesk() }
        cancelAutomaticReconnect()
        log(status)
        writeDiagnostics()
    }

    private func rememberCurrentDesk() {
        guard let deskID else { return }
        let record = RememberedDesk(id: deskID, name: deskName)
        do {
            try connectionStore.save(record)
            rememberedDesk = record
        } catch {
            log("记住桌子失败：\(error.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        let uuid = characteristic.uuid.uuidString.lowercased()
        if uuid == LinakProtocol.dpg {
            if let error { log("DPG 通知不可用：\(error.localizedDescription)") }
            if phase == .initialising && dpgStep == nil { runDPG(.base) }
        } else if let error { log("通知订阅失败：\(error.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        let uuid = characteristic.uuid.uuidString.lowercased()
        if uuid == LinakProtocol.height { heightReadPending = false }
        if let error {
            log("读取失败：\(error.localizedDescription)")
            if motion != nil { stop(reason: "高度或控制器数据读取失败") }
            return
        }
        guard let data = characteristic.value else { return }
        switch uuid {
        case LinakProtocol.height:
            guard let reading = LinakProtocol.decodeTelemetry(data) else {
                if motion != nil { stop(reason: "高度数据格式不兼容") }
                return
            }
            telemetry = reading
            telemetryAt = now
            hasFreshHeight = true
            heightCM = reading.heightCM(baseMM: baseMM)
        case LinakProtocol.dpg: receivedDPG(data)
        case LinakProtocol.error:
            // A zero-valued event clears an error. Never resume a previous motion.
            if data.contains(where: { $0 != 0 }) {
                cooldownUntil = now + 2
                stop(reason: "桌子报告故障或碰撞，已停止：\(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
        default: break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        busyWrites.remove(characteristic.uuid.uuidString.lowercased())
        if let error {
            log("蓝牙写入失败：\(error.localizedDescription)")
            if motion != nil { stop(reason: "发送升降指令失败") }
        }
        flushStop()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        flushStop()
    }

    private func log(_ text: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("\(stamp)  \(text)")
        if logs.count > 40 { logs.removeFirst(logs.count - 40) }
    }

    func diagnosticsJSON() -> Data {
        var result: [String: Any] = [
            "bluetooth": bluetoothText, "bluetoothAuthorization": CBManager.authorization.rawValue,
            "phase": phase.rawValue, "status": status, "desk": deskName,
            "scanning": isScanning, "moving": isMoving, "baseKnown": baseKnown,
            "userReady": userReady, "baseSource": baseSource,
            "nearbyDesks": desks.map { ["id": $0.id.uuidString, "name": $0.name, "rssi": $0.rssi] as [String: Any] },
            "characteristics": characteristics.keys.sorted(), "logs": logs
        ]
        if let heightCM { result["heightCM"] = heightCM }
        result["favorites"] = favorites.map { ["id": $0.id.uuidString, "name": $0.name, "heightCM": $0.heightCM] as [String: Any] }
        if let targetCM { result["targetCM"] = targetCM }
        if let peripheral { result["deskID"] = peripheral.identifier.uuidString }
        if let rememberedDesk {
            result["rememberedDesk"] = ["id": rememberedDesk.id.uuidString, "name": rememberedDesk.name]
        }
        if let motionSource { result["motionSource"] = String(describing: motionSource) }
        if baseKnown { result["baseMM"] = baseMM }
        return (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private func writeDiagnostics() {
        guard let diagnosticsPath else { return }
        try? diagnosticsJSON().write(to: URL(fileURLWithPath: diagnosticsPath), options: .atomic)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(data: diagnosticsJSON(), encoding: .utf8) ?? "", forType: .string)
    }

    func prepareToQuit() {
        if phase == .ready && userReady { rememberCurrentDesk() }
        isQuitting = true
        cancelAutomaticReconnect()
        automaticReconnectSuppressed = true
        connectTimer?.invalidate(); connectTimer = nil
        stop(showStatus: false)
        stopScan()
        writeDiagnostics()
    }
}

func format(_ value: Double) -> String { String(format: "%.1f", value) }
