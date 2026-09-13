import Cocoa
import IOBluetooth

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var timer: Timer?

    private let preferredDeviceAddressKey = "preferredDeviceAddress"
    private let legacyDeviceAddress = "38:47:12:22:F9:10"
    var device: IOBluetoothDevice?
    private var connectionState: ConnectionState = .disconnected
    private var statusMessage: String?
    private var connectionDeadline: Date?

    private enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        loadPreferredDevice()

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleBluetooth)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        updateStatus()

        timer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(updateStatus),
            userInfo: nil,
            repeats: true
        )
    }

    func isConnected() -> Bool {
        return device?.isConnected() ?? false
    }

    private func loadPreferredDevice() {
        let address = UserDefaults.standard.string(forKey: preferredDeviceAddressKey)
            ?? legacyDeviceAddress
        device = IOBluetoothDevice(addressString: address)
    }

    @objc func toggleBluetooth() {

        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }

        guard connectionState != .connecting else {
            return
        }

        guard let device = device else {
            connectionState = .failed
            statusMessage = "Устройство не выбрано"
            updateStatus()
            return
        }

        connectionState = .connecting
        statusMessage = device.name ?? device.addressString
        updateStatus()

        DispatchQueue.global(qos: .userInitiated).async {

            if device.isConnected() {
                device.closeConnection()
                DispatchQueue.main.async {
                    self.connectionState = .disconnected
                    self.statusMessage = nil
                    self.updateStatus()
                }
            } else {
                let result = device.openConnection()
                DispatchQueue.main.async {
                    self.connectionState = result == kIOReturnSuccess ? .connecting : .failed
                    self.statusMessage = result == kIOReturnSuccess
                        ? nil
                        : "Не удалось подключиться (код \(result))"
                    self.connectionDeadline = result == kIOReturnSuccess
                        ? Date().addingTimeInterval(12)
                        : nil
                    self.updateStatus()
                }
            }
        }
    }

    @objc func updateStatus() {

        guard let button = statusItem.button else {
            return
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 17,
            weight: .medium
        )

        guard let image = NSImage(
            systemSymbolName: "sunglasses",
            accessibilityDescription: "RB Meta"
        )?.withSymbolConfiguration(configuration) else {
            return
        }

        if isConnected() {

            connectionState = .connected
            connectionDeadline = nil
            statusMessage = nil
            image.isTemplate = false
            button.image = image
            button.contentTintColor = .systemGreen
            button.toolTip = "\(deviceLabel) — подключены"

        } else {

            if connectionState == .connected {
                connectionState = .disconnected
            }
            if let deadline = connectionDeadline, Date() >= deadline {
                connectionState = .failed
                connectionDeadline = nil
                statusMessage = "Подключение не удалось за 12 секунд"
            }

            image.isTemplate = true
            button.image = image
            button.contentTintColor = nil
            switch connectionState {
            case .connecting:
                button.toolTip = "\(deviceLabel) — подключение…"
            case .failed:
                button.toolTip = statusMessage ?? "Не удалось подключиться"
            default:
                button.toolTip = "\(deviceLabel) — отключены"
            }
        }
    }

    private var deviceLabel: String {
        device?.name ?? device?.addressString ?? "Очки не выбраны"
    }

    private func showMenu() {
        let menu = NSMenu()
        let stateTitle: String
        switch connectionState {
        case .connected: stateTitle = "\(deviceLabel) — подключены"
        case .connecting: stateTitle = "\(deviceLabel) — подключение…"
        case .failed: stateTitle = statusMessage ?? "Ошибка подключения"
        case .disconnected: stateTitle = "\(deviceLabel) — отключены"
        }

        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let toggleTitle = isConnected() ? "Отключить" : "Подключить"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = connectionState != .connecting && device != nil
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let devicesMenu = NSMenu(title: "Выбрать устройство")
        let pairedDevices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        if pairedDevices.isEmpty {
            let emptyItem = NSMenuItem(title: "Нет сопряжённых устройств", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            devicesMenu.addItem(emptyItem)
        } else {
            for pairedDevice in pairedDevices {
                let title = pairedDevice.name ?? pairedDevice.addressString ?? "Неизвестное устройство"
                let item = NSMenuItem(title: title, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pairedDevice.addressString
                item.state = pairedDevice.addressString == device?.addressString ? .on : .off
                devicesMenu.addItem(item)
            }
        }
        let chooseItem = NSMenuItem(title: "Выбрать устройство", action: nil, keyEquivalent: "")
        chooseItem.submenu = devicesMenu
        menu.addItem(chooseItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Завершить RB Meta", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func toggleFromMenu() {
        toggleBluetooth()
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        UserDefaults.standard.set(address, forKey: preferredDeviceAddressKey)
        device = IOBluetoothDevice(addressString: address)
        connectionState = isConnected() ? .connected : .disconnected
        statusMessage = nil
        connectionDeadline = nil
        updateStatus()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
