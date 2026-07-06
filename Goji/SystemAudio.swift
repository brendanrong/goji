import CoreAudio

/// Mutes the default output device while dictating so music or video audio
/// doesn't bleed into the mic, then restores the previous state. Devices
/// without a settable mute control (some HDMI outputs) are left alone.
enum SystemAudio {
    private static var restore: (device: AudioDeviceID, wasMuted: UInt32)?

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static func muteOutput() {
        guard restore == nil else { return }

        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return }

        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &muteAddress),
              AudioObjectIsPropertySettable(device, &muteAddress, &settable) == noErr,
              settable.boolValue else { return }

        var current: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &current) == noErr else { return }

        var on: UInt32 = 1
        guard AudioObjectSetPropertyData(device, &muteAddress, 0, nil, muteSize, &on) == noErr else { return }
        restore = (device, current)
    }

    /// No-op unless muteOutput actually muted something.
    static func restoreOutput() {
        guard let saved = restore else { return }
        restore = nil
        var value = saved.wasMuted
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(saved.device, &muteAddress, 0, nil, size, &value)
    }
}
