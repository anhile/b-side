import Combine
import CoreAudio
import CoreBluetooth
import IOBluetooth

/// Where the Mac's sound can go: the speakers, headphones, a display, an
/// AirPlay or Bluetooth device that is connected.
struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
    /// The system's lasting name for it; a Bluetooth device's has its address.
    let uid: String
    /// The Mac's own speakers or headphone jack.
    var isBuiltIn = false
}

/// A paired Bluetooth speaker or pair of headphones that is not connected.
struct BluetoothOutput: Identifiable, Equatable {
    /// Its address, as "aa-bb-cc-dd-ee-ff".
    let id: String
    let name: String
}

/// The Mac's sound outputs and the one in use, kept up to date as devices
/// come and go. Choosing one changes the system's output, as the Sound menu
/// does: the player page plays through whatever the system plays through,
/// and WebKit cannot send one page's sound elsewhere.
@MainActor
final class AudioOutputs: ObservableObject {
    static let shared = AudioOutputs()

    @Published private(set) var devices: [AudioOutput] = []
    @Published private(set) var current: AudioDeviceID = kAudioObjectUnknown
    /// Empty until the user asks for them: reading the paired devices makes
    /// macOS ask whether B-Side may use Bluetooth. Read only while the menu
    /// is open, never at launch.
    @Published private(set) var paired: [BluetoothOutput] = []
    @Published private(set) var showsBluetooth = Settings.bool(Keys.bluetoothOutputs)
    /// Snapshots: the device Now Playing says the sound goes to.
    var sampleElsewhere: AudioOutput?

    /// The device the sound goes to when it is not the Mac's own: named on
    /// Now Playing, so a pair of headphones left on in another room is not
    /// a mystery.
    var elsewhere: AudioOutput? {
        if let sampleElsewhere { return sampleElsewhere }
        guard let device = devices.first(where: { $0.id == current }), !device.isBuiltIn else { return nil }
        return device
    }

    /// The Bluetooth device being connected, to get the sound once it is there.
    private var wanted: (address: String, since: Date)?

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private init() {
        read()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(Self.system, &address, .main) { [weak self] _, _ in
                Task { @MainActor in self?.read() }
            }
        }
    }

    func select(_ device: AudioOutput) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(Self.system, &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        EventLog.write("output\t\(device.name)" + (status == noErr ? "" : "\tfailed, status \(status)"))
        read()
    }

    /// macOS has been asked about Bluetooth and said yes. Read without
    /// asking: the question is asked only from "Connect a Bluetooth
    /// Device…", never by a menu opening (as it was until 2026-10-03).
    private static var allowed: Bool { CBManager.authorization == .allowedAlways }

    /// From the menu item, once: macOS asks about Bluetooth, and the
    /// paired devices are listed from then on.
    func showBluetooth() {
        Settings.defaults.set(true, forKey: Keys.bluetoothOutputs)
        showsBluetooth = true
        paired = Self.pairedAudio()
    }

    /// For the menu, as it opens: only once allowed, so no question pops.
    func refreshPaired() {
        paired = showsBluetooth && Self.allowed ? Self.pairedAudio() : []
    }

    /// The paired devices are listed; else the item that asks.
    var listsPaired: Bool { showsBluetooth && Self.allowed }

    /// Connects the device; the sound goes to it when it has connected.
    func connect(_ device: BluetoothOutput) {
        wanted = (device.id, Date())
        let address = device.id, name = device.name
        DispatchQueue.global(qos: .userInitiated).async {
            let status = IOBluetoothDevice(addressString: address)?.openConnection() ?? kIOReturnNoDevice
            Task { @MainActor in
                EventLog.write("output\tconnecting \(name)" + (status == kIOReturnSuccess ? "" : "\tfailed, status \(status)"))
                self.read()
                self.refreshPaired()
            }
        }
    }

    private func read() {
        devices = Self.ids().compactMap { id in
            guard Self.canBeOutput(id), let name = Self.string(of: id, kAudioObjectPropertyName) else { return nil }
            return AudioOutput(id: id, name: name, symbol: Self.symbol(of: id),
                               uid: Self.string(of: id, kAudioDevicePropertyDeviceUID) ?? "",
                               isBuiltIn: Self.value(of: id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn)
        }
        current = Self.value(of: Self.system, kAudioHardwarePropertyDefaultOutputDevice) ?? kAudioObjectUnknown
        guard let wanted else { return }
        if Date().timeIntervalSince(wanted.since) > Tuning.bluetoothConnectSeconds {
            self.wanted = nil
        } else if let arrived = devices.first(where: { $0.uid.lowercased().contains(wanted.address.lowercased()) }) {
            self.wanted = nil
            select(arrived)
        }
    }

    /// Paired audio devices that are not connected; a connected one is among
    /// the system's outputs already.
    private static func pairedAudio() -> [BluetoothOutput] {
        let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return all.compactMap { device in
            guard device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio),
                  !device.isConnected(), let address = device.addressString else { return nil }
            return BluetoothOutput(id: address, name: device.name ?? address)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func ids() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Device IDs, transport types and flags are all 32-bit numbers.
    private static func value(of object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Has output streams, and the system lets it be the default output.
    private static func canBeOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        return value(of: id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioObjectPropertyScopeOutput) == 1
    }

    private static func string(of id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func symbol(of id: AudioDeviceID) -> String {
        switch value(of: id, kAudioDevicePropertyTransportType) {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        default: return "hifispeaker"
        }
    }
}
