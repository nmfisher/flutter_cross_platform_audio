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
        print(call.method)
        switch call.method {
        case "initializeAudioPlayer":
            if audioPlayer != nil {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "An AudioPlayer instance already exists, call destroyAudioPlayer", details: nil))
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let sampleRate = args["sampleRate"] as? Double,
                  let channels = args["channels"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for initializeAudioPlayer", details: nil))
                return
            }
            initializeAudioPlayer(sampleRate: sampleRate, channels: channels, result: result)
            break
        case "destroyAudioPlayer":
            audioPlayer = nil
            result(nil)
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
        case "streamComplete":
            if audioPlayer == nil {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "No audio player available", details: nil))
            } else {
                audioPlayer?.waitForCompletion(result:result)
            }
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
        DispatchQueue.main.async {
            let int16Data = audioData.data.withUnsafeBytes { rawBuffer in
                Array(rawBuffer.bindMemory(to: Int16.self))
            }
            self.audioPlayer?.addAudioData(int16Data)
            result(nil)
        }
    }
}

class AudioPlayer {

    var sampleRate:Int? = nil
    var samplesPlayed = 0
    var samplesSubmitted = 0
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    var buffer:AVAudioPCMBuffer? = nil
    var bufferSize:Int? = nil
    var format:AVAudioFormat? = nil
    private var isPlaying = false
    private var pendingAudioData: [Int16] = []
    
    let realtimeQueue = DispatchQueue.global(qos: .userInteractive)
    
    init(sampleRate: Int) {
        self.sampleRate = sampleRate
        self.bufferSize = sampleRate / 10
        print("Using bufferSize \(bufferSize)")
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
        

        
    }
    
    func start() {
        isPlaying = true
        fillBuffer()
        player.play()
    }
    
    func stop() {
        isPlaying = false
        player.stop()
    }
    
    
    func fillBuffer() {
        
        let bufferFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(sampleRate!),
                                         channels: 1,
                                         interleaved: false)
        
        let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat!, frameCapacity: AVAudioFrameCount(bufferSize!))

        let availableSpace = Int(buffer!.frameCapacity)
        let framesToCopy = min(pendingAudioData.count, availableSpace)
        if let channelData = buffer?.floatChannelData?[0] {            
            for i in 0..<framesToCopy {
                channelData[i] = Float(Double(pendingAudioData[i]) / 32767.0)
            }
            
        } else {
            
        }
        
        buffer!.frameLength = AVAudioFrameCount(framesToCopy)
        
        if(framesToCopy > 0) {
            pendingAudioData.removeFirst(framesToCopy)
            player.scheduleBuffer(buffer!, completionCallbackType: .dataPlayedBack) { _ in
                self.samplesPlayed += Int(buffer!.frameLength)
            }
            DispatchQueue.main.async {
                if self.isPlaying {
                    self.fillBuffer()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
                if self?.isPlaying == true {
                    self?.fillBuffer()
                }
            }
        }
    }
    
    func waitForCompletion(result: @escaping FlutterResult) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
            if(self?.samplesPlayed == self?.samplesSubmitted) {
                result(nil)
            } else {
                self?.waitForCompletion(result: result)
            }
        }
    }

    func addAudioData(_ newData: [Int16]) {
        guard !newData.isEmpty else {
            return
        }
        pendingAudioData.append(contentsOf: newData)
        samplesSubmitted += newData.count
    }
    
}
