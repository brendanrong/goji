import AVFoundation

/// Captures microphone audio and accumulates 16 kHz mono Float32 samples,
/// the format Parakeet expects. Start on key press, stop on release.
///
/// Built on AVCaptureSession bound to a specific device, NOT AVAudioEngine.
/// AVAudioEngine.inputNode always wraps the *system default* input in its own
/// aggregate device the moment it's created, before any device override can
/// take effect. With Bluetooth headphones as the default that wakes the HFP
/// mic on every dictation; once the Bluetooth audio stack wedges, the HAL IO
/// thread never starts and every recording (any mic) delivers zero buffers
/// until a reboot. AVCaptureSession talks to the chosen device directly and
/// never touches the default input. Verified with scripts/mic-probe*.swift.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let sampleRate: Double = 16_000

    /// Mic level callback (0...1), delivered on the main queue while recording.
    var onLevel: ((Float) -> Void)?

    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "goji.audio.capture")
    private let lock = NSLock()
    private var samples: [Float] = []
    private var buffersReceived = 0

    /// True when the mic was opened but never delivered a single buffer.
    /// That's the "audio system is wedged" signature; surface it to the user.
    var deliveredNoAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffersReceived == 0
    }

    func start(deviceUID: String? = nil) throws {
        teardown()

        lock.lock()
        samples.removeAll()
        buffersReceived = 0
        lock.unlock()

        let device: AVCaptureDevice?
        if let deviceUID, let chosen = AVCaptureDevice(uniqueID: deviceUID) {
            device = chosen
        } else {
            // Unset or unplugged: fall back to whatever the system default is.
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device else {
            throw GojiError("No microphone input available. Check mic permission in System Settings > Privacy & Security > Microphone.")
        }

        let session = AVCaptureSession()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw GojiError("Couldn't open \(device.localizedName): \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else {
            throw GojiError("Couldn't open \(device.localizedName).")
        }
        session.addInput(input)

        // Ask capture for Parakeet's format directly; no manual converter.
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw GojiError("Couldn't read from \(device.localizedName).")
        }
        session.addOutput(output)

        self.session = session
        session.startRunning()
        guard session.isRunning else {
            teardown()
            throw GojiError("\(device.localizedName) didn't start.")
        }
    }

    func stop() -> [Float] {
        teardown()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// Stops capture and releases the session. Idempotent.
    private func teardown() {
        if let session, session.isRunning {
            session.stopRunning()
        }
        session = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        pcm.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        ) == noErr, let channel = pcm.floatChannelData?.pointee else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: frames))
        lock.lock()
        samples.append(contentsOf: chunk)
        buffersReceived += 1
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
