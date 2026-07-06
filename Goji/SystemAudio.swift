import CoreAudio

/// Silences the default output device while dictating, then restores it.
/// Prefers the device's real mute switch; falls back to zeroing the volume for
/// outputs without one (HDMI/DisplayPort monitors, some USB DACs). Devices
/// exposing neither control are left alone.
enum SystemAudio {
    private struct Saved {
        let device: AudioDeviceID
        let mute: UInt32?
        let volumes: [(element: UInt32, value: Float32)]
    }
    private static var saved: Saved?

    static func muteOutput() {
        guard saved == nil, let device = defaultOutputDevice() else { return }

        if isSettable(device, kAudioDevicePropertyMute, element: 0),
           let previous: UInt32 = read(device, kAudioDevicePropertyMute, element: 0),
           write(device, kAudioDevicePropertyMute, element: 0, value: UInt32(1)) {
            saved = Saved(device: device, mute: previous, volumes: [])
            return
        }

        // No mute switch: zero the volume instead. Master element when the
        // device has one, otherwise per channel (left 1, right 2).
        let elements: [UInt32] = isSettable(device, kAudioDevicePropertyVolumeScalar, element: 0) ? [0] : [1, 2]
        var volumes: [(element: UInt32, value: Float32)] = []
        for element in elements {
            guard isSettable(device, kAudioDevicePropertyVolumeScalar, element: element),
                  let previous: Float32 = read(device, kAudioDevicePropertyVolumeScalar, element: element),
                  write(device, kAudioDevicePropertyVolumeScalar, element: element, value: Float32(0)) else { continue }
            volumes.append((element, previous))
        }
        if !volumes.isEmpty {
            saved = Saved(device: device, mute: nil, volumes: volumes)
        }
    }

    /// No-op unless muteOutput actually changed something.
    static func restoreOutput() {
        guard let s = saved else { return }
        saved = nil
        if let mute = s.mute {
            _ = write(s.device, kAudioDevicePropertyMute, element: 0, value: mute)
        }
        for volume in s.volumes {
            _ = write(s.device, kAudioDevicePropertyVolumeScalar, element: volume.element, value: volume.value)
        }
    }

    // MARK: - CoreAudio plumbing

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return (status == noErr && device != kAudioObjectUnknown) ? device : nil
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector, element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func isSettable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var address = outputAddress(selector, element: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func read<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: UInt32) -> T? {
        var address = outputAddress(selector, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func write<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: UInt32, value: T) -> Bool {
        var address = outputAddress(selector, element: element)
        var v = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }
}
