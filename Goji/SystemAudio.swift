import CoreAudio

/// Volume control over the default output while dictating. Ducks to a
/// fraction of the current level and restores afterward. Outputs exposing no
/// volume control (some HDMI/DisplayPort monitors) can't be ducked; callers
/// fall back to pausing media instead.
enum SystemAudio {
    private struct Saved {
        let device: AudioDeviceID
        let volumes: [(element: UInt32, value: Float32)]
    }
    private static var saved: Saved?

    /// Drops the output volume to ~20% of its current level. Returns false
    /// when the device has no volume control.
    static func duckOutput() -> Bool {
        guard saved == nil else { return true }
        guard let device = defaultOutputDevice() else { return false }

        // Master element when the device has one, otherwise per channel.
        let elements: [UInt32] = isSettable(device, kAudioDevicePropertyVolumeScalar, element: 0) ? [0] : [1, 2]
        var volumes: [(element: UInt32, value: Float32)] = []
        for element in elements {
            guard isSettable(device, kAudioDevicePropertyVolumeScalar, element: element),
                  let previous: Float32 = read(device, kAudioDevicePropertyVolumeScalar, element: element),
                  write(device, kAudioDevicePropertyVolumeScalar, element: element, value: Float32(previous * 0.2)) else { continue }
            volumes.append((element, previous))
        }
        guard !volumes.isEmpty else { return false }
        saved = Saved(device: device, volumes: volumes)
        return true
    }

    /// No-op unless duckOutput actually changed something.
    static func restoreOutput() {
        guard let s = saved else { return }
        saved = nil
        for volume in s.volumes {
            _ = write(s.device, kAudioDevicePropertyVolumeScalar, element: volume.element, value: volume.value)
        }
    }

    /// True when any app is currently playing audio through the default
    /// output. Gates the media-key pause so it can't START playback that
    /// wasn't running.
    static func outputIsActive() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
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
