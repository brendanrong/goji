// Diagnostic: capture ~1.5 s from a specific mic via AVCaptureSession (binds to
// the device directly, never touches the system default input). Run on the Mac:
//   swift scripts/mic-probe-capture.swift [deviceUID]
import AVFoundation

final class Sink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var buffers = 0
    var frames = 0
    var peak: Float = 0
    var format = ""
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        buffers += 1
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return }
        if format.isEmpty { format = "\(asbd.mChannelsPerFrame)ch @\(asbd.mSampleRate)Hz flags=\(asbd.mFormatFlags) bits=\(asbd.mBitsPerChannel)" }
        let n = CMSampleBufferGetNumSamples(sampleBuffer)
        frames += n
        guard let pcm = AVAudioFormat(streamDescription: withUnsafePointer(to: asbd) { $0 }),
              let buf = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(n), into: buf.mutableAudioBufferList)
        if let ch = buf.floatChannelData?.pointee {
            for i in 0..<n { peak = max(peak, abs(ch[i])) }
        }
    }
}

let wantUID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let device: AVCaptureDevice?
if let wantUID { device = AVCaptureDevice(uniqueID: wantUID) } else { device = AVCaptureDevice.default(for: .audio) }
guard let device else { print("no device for \(wantUID ?? "default")"); exit(1) }
print("device: \(device.localizedName) uid=\(device.uniqueID)")

let session = AVCaptureSession()
let input = try AVCaptureDeviceInput(device: device)
session.addInput(input)
let output = AVCaptureAudioDataOutput()
output.audioSettings = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsNonInterleaved: false,
    AVLinearPCMIsBigEndianKey: false,
]
let sink = Sink()
output.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "probe.audio"))
session.addOutput(output)
let t0 = Date()
session.startRunning()
print("startRunning took \(Int(Date().timeIntervalSince(t0) * 1000)) ms, running=\(session.isRunning)")
Thread.sleep(forTimeInterval: 1.5)
session.stopRunning()
print("RESULT buffers=\(sink.buffers) frames=\(sink.frames) format=[\(sink.format)] peak=\(sink.peak)")
