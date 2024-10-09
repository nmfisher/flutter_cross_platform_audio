import Cocoa
import FlutterMacOS
import AVFoundation

public class CrossPlatformAudioNativePlugin: NSObject, FlutterPlugin {
    private var audioPlayer: AudioPlayer?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.nick-fisher.cross_platform_audio_native", binaryMessenger: registrar.messenger)
        let instance = CrossPlatformAudioNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print(call.method);
        switch call.method {
        case "initializeAudioPlayer":
            guard let args = call.arguments as? [String: Any],
                  let sampleRate = args["sampleRate"] as? Double,
                  let channels = args["channels"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for initializeAudioPlayer", details: nil))
                return
            }
            initializeAudioPlayer(sampleRate: sampleRate, channels: channels, result: result)
            break
        case "startPlayback":
            startPlayback(result: result)
            break
        case "stopPlayback":
            stopPlayback(result: result)
            break
        case "addAudioData":
            guard let args = call.arguments as? [String: Any],
                  let audioData = args["audioData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for addAudioData", details: nil))
                return
            }
            addAudioData(audioData: audioData, result: result)
            break
        default:
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Unknown method \(call.method)", details: nil))
        }
    }
    
    private func initializeAudioPlayer(sampleRate: Double, channels: Int, result: @escaping FlutterResult) {
        audioPlayer = AudioPlayer(sampleRate: Int(sampleRate))
        result(nil)
    }
    
    private func startPlayback(result: @escaping FlutterResult) {
        audioPlayer?.start()
        result(nil)
    }
    
    private func stopPlayback(result: @escaping FlutterResult) {
        audioPlayer?.stop()
        result(nil)
    }
    
    private func addAudioData(audioData: FlutterStandardTypedData, result: @escaping FlutterResult) {
        let int16Data = audioData.data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Int16.self))
        }
        audioPlayer?.addAudioData(int16Data)
        result(nil)
    }
}

class AudioPlayer {
    var sampleRate:Int? = nil
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    var buffer:AVAudioPCMBuffer? = nil
    var bufferSize:Int? = nil
    var format:AVAudioFormat? = nil
    private var isPlaying = false
    private var pendingAudioData: [Int16] = []
    
    init(sampleRate: Int) {
        self.sampleRate = sampleRate
        self.bufferSize = sampleRate / 10
        player.volume = 1.0
        
        engine.attach(player)
        
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Double(sampleRate),
                                      channels: 1,
                                      interleaved: false)
        
        engine.connect(player, to: engine.mainMixerNode, format:outFormat)
        
        
        do {
            try engine.start()
        } catch {
            print("Error starting AVAudioEngine: \(error)")
        }
        
        let bufferFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(sampleRate),
                                         channels: 1,
                                         interleaved: false)
        
        buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat!, frameCapacity: AVAudioFrameCount(bufferSize!))
        
        //        // Generate a simple sine wave
        //        let bufferSize = 24000
        //        let frequency: Double = 440.0 // A4
        //
        //        buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat!, frameCapacity: AVAudioFrameCount(bufferSize))!
        //
        //        if let channelData = buffer?.int16ChannelData?[0] {
        //                  let twoPi = 2.0 * Double.pi
        //                  for n in 0..<Int(bufferSize) {
        //                      var step = Double(n) / Double(sampleRate)
        //
        //                      let value = sin(twoPi * step * frequency)
        //                      channelData[n] = Int16(value * 32767)
        //                  }
        //              }
        //        buffer!.frameLength = buffer!.frameCapacity
        //
        //        let converter = AVAudioConverter(from: buffer!.format, to: outFormat!)
        //
        //        // 3. Create an output buffer with the desired format
        //        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outFormat!, frameCapacity: buffer!.frameLength) else {
        //            print("Error creating output buffer")
        //            return
        //        }
        //
        //
        //        // 4. Perform the conversion.  The converter will fill outputBuffer
        //        var error: NSError? = nil
        //        let status = converter?.convert(to: outputBuffer, error: &error, withInputFrom: { (inNumPackets, outStatus) -> AVAudioBuffer? in
        //            outStatus.pointee = AVAudioConverterInputStatus.haveData
        //            return self.buffer!
        //        })
        //
        //        if status != .error {
        //            player.scheduleBuffer(outputBuffer, at: nil, options: .loops) { } // Loop indefinitely
        //            player.play()
    }
    
    func start() {
        isPlaying = true
        fillAndScheduleBuffer()
        player.play()
    }
    
    func stop() {
        isPlaying = false
        player.stop()
    }
    
    private func scheduleBuffer() {
        player.scheduleBuffer(buffer!) {
            if self.isPlaying {
                DispatchQueue.main.async {
                    self.fillAndScheduleBuffer()
                }
            }
        }
    }
    
    
    func fillAndScheduleBuffer() {
        let availableSpace = Int(buffer!.frameCapacity)
        let framesToCopy = min(pendingAudioData.count, availableSpace)
       
        if let channelData = buffer?.floatChannelData?[0] {
            
            for i in 0..<framesToCopy {
                channelData[i] = Float(Double(pendingAudioData[i]) / 32767.0)
            }
            
        } else {
           
        }

        buffer!.frameLength = AVAudioFrameCount(framesToCopy)       
        pendingAudioData.removeFirst(framesToCopy)
        scheduleBuffer()
    }
    
    
    func addAudioData(_ newData: [Int16]) {
        guard !newData.isEmpty else {
            return
        }
        pendingAudioData.append(contentsOf: newData)
    }
    
}
