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
///
/// Two idle states, chosen by `prepare(deviceUID:instantStart:)`:
/// - Cold (default): the session is built but stopped. Key-down pays
///   startRunning (~55 ms to first buffer) and whatever was said on the
///   instant of the press is lost. No mic indicator while idle.
/// - Instant start (opt-in): the session keeps running between dictations
///   and the last second of audio sits in a RAM-only ring buffer. Key-down
///   flips a flag and prepends up to `preRollSeconds` of what came before
///   the press. macOS shows the mic indicator the whole time; that is the
///   trade, and Settings says so. Never armed on Bluetooth or unknown
///   transports: an idle open Bluetooth mic pins the headset in HFP and
///   degrades playback, and it is the exact device class behind the wedge
///   above. Nothing is transcribed or kept beyond the ring while idle.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let sampleRate: Double = 16_000
    /// Pre-press audio prepended to a dictation when instant start is armed.
    static let preRollSeconds: Double = 0.45
    /// Ring capacity while idle. Only the tail (`preRollSeconds`) is ever read.
    private static let ringSeconds: Double = 1.0

    /// Mic level callback (0...1), delivered on the main queue while recording.
    var onLevel: ((Float) -> Void)?

    private enum Mode {
        /// Session stopped, or running only to feed the ring.
        case idle
        /// Buffers go into `samples`.
        case recording
    }

    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "goji.audio.capture")
    private let lock = NSLock()
    private var mode: Mode = .idle
    private var samples: [Float] = []
    private var buffersReceived = 0
    private var startedAt = Date()
    /// The device the idle, pre-built session is bound to.
    private var preparedDeviceID: String?
    /// Name of the mic the last recording actually used (after any fallback).
    private(set) var deviceName = "microphone"
    /// UID of the device the current session is bound to (for the media-pause guard).
    private(set) var deviceUID: String?

    /// True while the session runs between dictations to feed the ring.
    private(set) var idleCapturing = false
    private var ring = [Float](repeating: 0, count: Int(AudioRecorder.ringSeconds * AudioRecorder.sampleRate))
    private var ringWrite = 0
    private var ringFilled = 0
    /// Pre-roll samples included in the current recording (for the log).
    private(set) var lastPreRollSamples = 0

    /// True when the mic was opened but never delivered a single buffer.
    /// That's the "audio system is wedged" signature; surface it to the user.
    var deliveredNoAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffersReceived == 0
    }

    /// Build a session for the chosen mic so key-down only has to call
    /// startRunning (or, with instant start armed, nothing at all). Called at
    /// launch, after every stop, and when the mic or instant-start setting
    /// changes; cheap to call again when nothing changed.
    func prepare(deviceUID: String?, instantStart: Bool = false) {
        let resolved = resolveDevice(deviceUID)
        let armInstant = instantStart && Self.allowsIdleCapture(resolved)
        if let session, preparedFor(deviceUID), idleCapturing == armInstant,
           session.isRunning == armInstant, currentMode == .idle {
            return
        }
        teardown()
        do {
            let (session, device) = try buildSession(deviceUID: deviceUID)
            self.session = session
            preparedDeviceID = device.uniqueID
            deviceName = device.localizedName
            self.deviceUID = device.uniqueID
        } catch {
            Log.audio.error("prepare failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if instantStart && !armInstant {
            Log.audio.notice("instant start held back: \(self.deviceName, privacy: .public) is Bluetooth or an unknown transport")
        }
        guard armInstant, let session else { return }
        lock.lock()
        mode = .idle
        resetRingLocked()
        lock.unlock()
        session.startRunning()
        if session.isRunning {
            idleCapturing = true
            Log.audio.notice("instant start armed on \(self.deviceName, privacy: .public)")
        } else {
            Log.audio.error("instant start: session did not start for \(self.deviceName, privacy: .public), falling back to cold start")
        }
    }

    /// Begin a dictation. `includePreRoll` is ignored unless instant start is
    /// armed; the caller turns it off when media was playing at the press,
    /// because that audio predates the pause and would land in the transcript.
    func start(deviceUID: String? = nil, includePreRoll: Bool = true) throws {
        startedAt = Date()
        lastPreRollSamples = 0

        // Reuse the pre-built session when it's for this mic and that mic is
        // still around. A running session is only reusable if it is ours
        // feeding the ring; otherwise build one now (slower, still correct).
        let reusable = session != nil && preparedFor(deviceUID)
            && (session?.isRunning == false || idleCapturing)
        if !reusable {
            teardown()
            let (session, device) = try buildSession(deviceUID: deviceUID)
            self.session = session
            preparedDeviceID = device.uniqueID
            deviceName = device.localizedName
            self.deviceUID = device.uniqueID
            Log.audio.notice("built session on demand for \(device.localizedName, privacy: .public) in \(Log.ms(since: self.startedAt)) ms")
        }
        guard let session else { throw GojiError("No microphone session.") }

        if idleCapturing, session.isRunning {
            // Instant path: the mic is already flowing. Seed the take with the
            // ring tail and flip the mode; no device work on the hot path.
            lock.lock()
            samples = includePreRoll ? ringTailLocked(seconds: Self.preRollSeconds) : []
            lastPreRollSamples = samples.count
            buffersReceived = 0
            mode = .recording
            lock.unlock()
            Log.audio.notice("instant start: \(self.deviceName, privacy: .public) already open, pre-roll \(self.lastPreRollSamples * 1000 / Int(Self.sampleRate)) ms")
            return
        }

        lock.lock()
        samples.removeAll()
        buffersReceived = 0
        mode = .recording
        lock.unlock()
        Log.audio.notice("opening \(self.deviceName, privacy: .public) (system default: \(MicDevices.systemDefaultInput()?.name ?? "none", privacy: .public))")

        session.startRunning()
        guard session.isRunning else {
            Log.audio.error("session did not start for \(self.deviceName, privacy: .public)")
            teardown()
            throw GojiError("\(deviceName) didn't start.")
        }
        Log.audio.notice("session running after \(Log.ms(since: self.startedAt)) ms")
    }

    /// Ends the take and returns its samples. With instant start armed the
    /// session keeps running and goes back to feeding the ring.
    func stop() -> [Float] {
        let keepRunning = idleCapturing && session?.isRunning == true
        if !keepRunning {
            session?.stopRunning()
        }
        lock.lock()
        defer { lock.unlock() }
        let take = samples
        samples.removeAll()
        mode = .idle
        if keepRunning {
            resetRingLocked()
        }
        return take
    }

    private var currentMode: Mode {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    /// Wired transports only. Bluetooth (classic and LE), aggregate, virtual,
    /// AirPlay, continuity and anything unrecognised stays cold: we cannot
    /// tell what a virtual device wraps, and an idle open Bluetooth mic is
    /// the failure mode the whole recorder is built around avoiding.
    static func allowsIdleCapture(_ device: AVCaptureDevice?) -> Bool {
        guard let device, let transport = MicDevices.transportType(uid: device.uniqueID) else { return false }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeAVB:
            return true
        default:
            return false
        }
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
        deviceUID = nil
        idleCapturing = false
        lock.lock()
        mode = .idle
        resetRingLocked()
        lock.unlock()
    }

    // MARK: - Ring buffer (call with `lock` held)

    private func resetRingLocked() {
        ringWrite = 0
        ringFilled = 0
    }

    private func ringAppendLocked(_ chunk: [Float]) {
        let capacity = ring.count
        // A chunk larger than the ring: only its tail can matter.
        let start = max(0, chunk.count - capacity)
        for index in start..<chunk.count {
            ring[ringWrite] = chunk[index]
            ringWrite = (ringWrite + 1) % capacity
        }
        ringFilled = min(capacity, ringFilled + (chunk.count - start))
    }

    private func ringTailLocked(seconds: Double) -> [Float] {
        let capacity = ring.count
        let wanted = min(Int(seconds * Self.sampleRate), ringFilled)
        guard wanted > 0 else { return [] }
        var tail = [Float](repeating: 0, count: wanted)
        var read = (ringWrite - wanted + capacity) % capacity
        for index in 0..<wanted {
            tail[index] = ring[read]
            read = (read + 1) % capacity
        }
        return tail
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
        guard mode == .recording else {
            // Idle with instant start armed: remember the last second, nothing else.
            ringAppendLocked(chunk)
            lock.unlock()
            return
        }
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
