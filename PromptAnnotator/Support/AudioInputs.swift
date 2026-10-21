import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    var id: String
    var name: String
}

/// Lists input devices and, for one session, can switch the system input and raise its level.
enum AudioInputs {
    private static var previousDefault: AudioDeviceID?
    private static var previousVolume: RestoredVolume?

    private struct RestoredVolume {
        var device: AudioDeviceID
        var address: AudioObjectPropertyAddress
        var volume: Float32
    }

    static func devices() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard hasInput(id), let uid = stringProperty(kAudioDevicePropertyDeviceUID, device: id) else { return nil }
            let name = stringProperty(kAudioDevicePropertyDeviceNameCFString, device: id) ?? uid
            return AudioInputDevice(id: uid, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func beginSession(uid: String, raiseVolume: Bool) {
        if !uid.isEmpty, let requested = deviceID(forUID: uid) {
            let current = defaultInputID()
            if current != requested {
                previousDefault = current
                setDefaultInput(requested)
            }
        }
        if raiseVolume, let active = defaultInputID() {
            // Only store when we actually raised — a nil result must not clear a prior restore.
            if let raised = raiseInputVolume(active, target: 0.85) {
                previousVolume = raised
            }
        }
    }

    static func endSession() {
        if let previousVolume {
            setVolume(previousVolume.device, address: previousVolume.address, volume: previousVolume.volume)
            self.previousVolume = nil
        }
        if let previousDefault {
            setDefaultInput(previousDefault)
            self.previousDefault = nil
        }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let object = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(size))
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeRawPointer(buffer).assumingMemoryBound(to: AudioBufferList.self)
        return list.pointee.mNumberBuffers > 0
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        deviceIDs().first { stringProperty(kAudioDevicePropertyDeviceUID, device: $0) == uid }
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != 0 else { return nil }
        return id
    }

    private static func setDefaultInput(_ device: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &value)
    }

    /// Raises the input level when it is below `target`. Returns the prior value so the session can restore it.
    @discardableResult
    private static func raiseInputVolume(_ device: AudioDeviceID, target: Float32) -> RestoredVolume? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(device, &address) {
            address.mElement = 1
            guard AudioObjectHasProperty(device, &address) else { return nil }
        }
        var current: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr else { return nil }
        guard current < target else { return nil }
        let prior = RestoredVolume(device: device, address: address, volume: current)
        setVolume(device, address: address, volume: target)
        return prior
    }

    private static func setVolume(_ device: AudioDeviceID, address: AudioObjectPropertyAddress, volume: Float32) {
        var address = address
        var value = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }
}
