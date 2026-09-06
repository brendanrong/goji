// Diagnostic: list input devices, then record ~1.5 s from a given device UID
// (or the system default) through the same AVAudioEngine path Goji uses, and
// report how many buffers arrived and their RMS. Run on the Mac:
//   swift scripts/mic-probe.swift [deviceUID]
import AVFoundation
import CoreAudio

func prop<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ zero: T) -> T? {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    var value = zero
    let st = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
    return st == noErr ? value : nil
}
func str(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let st = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
    return st == noErr ? ((value as String?) ?? "?") : "?"
}
func inputChannels(_ id: AudioObjectID) -> Int {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    return UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
}

var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var ids = [AudioDeviceID](repeating: 0, count: Int(size) / 4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
let defaultIn = prop(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, AudioDeviceID(0)) ?? 0
print("default input id: \(defaultIn)")
for id in ids where inputChannels(id) > 0 {
    let rate = prop(id, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, Float64(0)) ?? 0
    let running = prop(id, kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal, UInt32(0)) ?? 0
    let alive = prop(id, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal, UInt32(0)) ?? 0
    print("  [\(id)] \(str(id, kAudioObjectPropertyName))  uid=\(str(id, kAudioDevicePropertyDeviceUID))  in=\(inputChannels(id))ch @\(Int(rate))Hz  runningSomewhere=\(running) alive=\(alive)")
}

let auth = AVCaptureDevice.authorizationStatus(for: .audio)
print("mic TCC status for this process: \(auth.rawValue) (0 notDetermined, 1 restricted, 2 denied, 3 authorized)")
if auth == .notDetermined {
    let sem = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .audio) { ok in print("requestAccess -> \(ok)"); sem.signal() }
    _ = sem.wait(timeout: .now() + 30)
}

let wantUID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
// SETDEFAULT=1: make the wanted device the system default input BEFORE the
// engine exists, so inputNode never binds to (and never wakes) a Bluetooth mic.
if ProcessInfo.processInfo.environment["SETDEFAULT"] == "1", let wantUID,
   var dev = ids.first(where: { str($0, kAudioDevicePropertyDeviceUID) == wantUID }) {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let st = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(4), &dev)
    print("set system default input -> \(dev) status \(st)")
    Thread.sleep(forTimeInterval: 0.5)
}
let engine = AVAudioEngine()
let input = engine.inputNode
if let wantUID, let unit = input.audioUnit,
   var dev = ids.first(where: { str($0, kAudioDevicePropertyDeviceUID) == wantUID }) {
    let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
    print("set CurrentDevice -> \(dev) status \(st)")
}
let fmt = input.outputFormat(forBus: 0)
print("inputNode format: \(fmt.channelCount)ch @\(fmt.sampleRate)Hz")
var buffers = 0
var peak: Float = 0
input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
    buffers += 1
    guard let ch = buf.floatChannelData?.pointee else { return }
    for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[i])) }
}
if let unit = input.audioUnit {
    var dev = AudioDeviceID(0)
    var sz = UInt32(4)
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, &sz)
    print("AUHAL CurrentDevice before start: \(dev)")
}
engine.prepare()
do { try engine.start(); print("engine started") } catch { print("engine.start FAILED: \(error)"); exit(1) }
if let unit = input.audioUnit {
    var dev = AudioDeviceID(0)
    var sz = UInt32(4)
    AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, &sz)
    print("AUHAL CurrentDevice after start: \(dev)")
}
Thread.sleep(forTimeInterval: 1.5)
input.removeTap(onBus: 0)
engine.stop()
print("RESULT buffers=\(buffers) peak=\(peak)")
