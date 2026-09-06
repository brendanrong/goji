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
    private var startedAt = Date()
    /// The device the idle, pre-built session is bound to.
    private var preparedDeviceID: String?
    /// Name of the mic the last recording actually used (after any fallback).
    private(set) var deviceName = "microphone"

    /// True when the mic was opened but never delivered a single buffer.
    /// That's the "audio system is wedged" signature; surface it to the user.
    var deliveredNoAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffersReceived == 0
    }

    /// Build (but don't start) a session for the chosen mic so key-down only
    /// has to call startRunning. Called after every stop and when the mic
    /// setting changes; cheap to call again with the same device.
    func prepare(deviceUID: String?) {
        if let session, !session.isRunning, preparedFor(deviceUID) {
            return
        }
        teardown()
        do {
            let (session, device) = try buildSession(deviceUID: deviceUID)
            self.session = session
            preparedDeviceID = device.uniqueID
            deviceName = device.localizedName
        } catch {
            Log.audio.error("prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func start(deviceUID: String? = nil) throws {
        lock.lock()
        samples.removeAll()
        buffersReceived = 0
        lock.unlock()
        startedAt = Date()

        // Reuse the pre-built session when it's for this mic and that mic is
        // still around; otherwise build one now (slower, still correct).
        if session == nil || session?.isRunning == true || !preparedFor(deviceUID) {
            teardown()
            let (session, device) = try buildSession(deviceUID: deviceUID)
            self.session = session
            preparedDeviceID = device.uniqueID
            deviceName = device.localizedName
            Log.audio.notice("built session on demand for \(device.localizedName, privacy: .public) in \(Log.ms(since: self.startedAt)) ms")
        }
        guard let session else { throw GojiError("No microphone session.") }
        Log.audio.notice("opening \(self.deviceName, privacy: .public) (system default: \(MicDevices.systemDefaultInput()?.name ?? "none", privacy: .public))")

        session.startRunning()
        guard session.isRunning else {
            Log.audio.error("session did not start for \(self.deviceName, privacy: .public)")
            teardown()
            throw GojiError("\(deviceName) didn't start.")
        }
        Log.audio.notice("session running after \(Log.ms(since: self.startedAt)) ms")
    }

    func stop() -> [Float] {
        session?.stopRunning()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// The device the prepared session was built for is still the one this
    /// UID resolves to (a setting of nil follows the system default, which can
    /// change between dictations).
    private func preparedFor(_ deviceUID: String?) -> Bool {
        resolveDevice(deviceUID)?.uniqueID == preparedDeviceID
    }

    private func resolveDevice(_ deviceUID: String?) -> AVCaptureDevice? {
        if let deviceUID, let chosen = AVCaptureDevice(uniqueID: deviceUID) {
            return chosen
        }
        // Unset or unplugged: fall back to whatever the system default is.
        return AVCaptureDevice.default(for: .audio)
    }

    private func buildSession(deviceUID: String?) throws -> (AVCaptureSession, AVCaptureDevice) {
        guard let device = resolveDevice(deviceUID) else {
            Log.audio.error("no capture device for uid \(deviceUID ?? "default", privacy: .public)")
            throw GojiError("No microphone input available. Check mic permission in System Settings > Privacy & Security > Microphone.")
        }
        if let deviceUID, device.uniqueID != deviceUID {
            Log.audio.error("chosen mic \(deviceUID, privacy: .public) not found, using default \(device.localizedName, privacy: .public)")
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
        return (session, device)
    }

    /// Stops capture and drops the session. Idempotent.
    private func teardown() {
        if let session, session.isRunning {
            session.stopRunning()
        }
        session = nil
        preparedDeviceID = nil
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
        let isFirst = buffersReceived == 1
        lock.unlock()
        if isFirst {
            // Key-down to first audio: the number that decides whether we
            // need a pre-roll buffer (see planning/v1.2-plan.md, item 4).
            Log.audio.notice("first buffer \(Log.ms(since: self.startedAt)) ms after start, \(frames) frames")
        }

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
