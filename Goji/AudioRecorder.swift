import AVFoundation
import CoreAudio

/// Captures microphone audio and accumulates 16 kHz mono Float32 samples,
/// the format Parakeet expects. Start on key press, stop on release.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    /// Mic level callback (0...1), delivered on the main queue while recording.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?

    func start(deviceUID: String? = nil) throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode

        // Route to the chosen mic; silently fall back to the system default.
        if let deviceUID,
           let deviceID = MicDevices.deviceID(forUID: deviceUID),
           let unit = input.audioUnit {
            var device = deviceID
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw GojiError("No microphone input available. Check mic permission in System Settings > Privacy & Security > Microphone.")
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw GojiError("Could not create 16 kHz audio format.")
        }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, outputFormat: outputFormat)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil

        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func append(_ buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil,
              converted.frameLength > 0,
              let channel = converted.floatChannelData?.pointee else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        // Level meter for the HUD waveform.
        var sum: Float = 0
        for sample in chunk {
            sum += sample * sample
        }
        let rms = (sum / Float(max(chunk.count, 1))).squareRoot()
        let level = min(1, rms * 9)
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
    }
}

struct GojiError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
