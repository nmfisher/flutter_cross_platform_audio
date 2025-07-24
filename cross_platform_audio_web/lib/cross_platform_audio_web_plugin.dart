import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as w;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:cross_platform_audio_platform_interface/cross_platform_audio_platform_interface.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';
import 'dart:js_interop' as ji;

class WebAudioService extends AudioService {
  late w.AudioContext context;

  @override
  void dispose() {
    // TODO: implement dispose
  }

  @override
  Future initialize() async {
  
  }

  @override
  Future<CancelPlayback> play(String path,
      {AudioSource source = AudioSource.File,
      String? package,
      void Function()? onBegin,
      void Function()? onComplete,
      int sampleRate = 16000,
      double speed = 1.0}) async {
    if (source == AudioSource.File) {
      throw Exception();
    }

    context = w.AudioContext(w.AudioContextOptions(sampleRate: sampleRate));

    var bufferSource = context.createBufferSource(); // creates a sound source
    var audioData = await rootBundle.load(path);
    var audioBuffer =
        await context.decodeAudioData(audioData.buffer.toJS).toDart;
    bufferSource.buffer = audioBuffer;
    bufferSource.connect(context
        .destination); // connect the source to the context's destination (the speakers)
    bufferSource.start();
    onBegin?.call();
    if (onComplete != null) {
      bufferSource.onended = onComplete.toJS;
    }
    return () async {
      bufferSource.stop();
    };
  }

  @override
  Future<CancelPlayback> playBuffer(Uint8List data,
      {AudioEncoding encoding = const PCM16(),
      void Function()? onBegin,
      void Function()? onComplete,
      int? sampleRate,
      bool? stereo,
      double? start}) async {
    try {
      context = w.AudioContext(w.AudioContextOptions(sampleRate: sampleRate ?? 24000));
      var bufferSource = w.AudioBufferSourceNode(context);
      late w.AudioBuffer audioBuffer;
      if (encoding == const PCM16()) {
        if (stereo == true) {
          throw Exception("TODO");
        }
        var f32Data = Float32List.fromList(data.buffer
            .asInt16List()
            .map((x) => x / 16384)
            .cast<double>()
            .toList());
        var jsData = f32Data.toJS;
        var options = w.AudioBufferOptions(
            numberOfChannels: 1,
            sampleRate: sampleRate!,
            length: data.length ~/ 2);
        audioBuffer = w.AudioBuffer(options);
        audioBuffer.copyToChannel(jsData, 0);
      } else if (encoding == PCMF32()) {
        var f32Data = data.buffer.asFloat32List(data.offsetInBytes);
        var jsData = f32Data.toJS;
        var options = w.AudioBufferOptions(
            numberOfChannels: 1,
            sampleRate: sampleRate!,
            length: data.length ~/ 2);
        audioBuffer = w.AudioBuffer(options);
        audioBuffer.copyToChannel(jsData, 0);
      } else {
        audioBuffer = await context.decodeAudioData(data.buffer.toJS).toDart;
      }
      bufferSource.buffer = audioBuffer;
      bufferSource.connect(context
          .destination); // connect the source to the context's destination (the speakers)
      late StreamSubscription listener;
      listener = bufferSource.onEnded.listen((event) {
        onComplete?.call();
      });

      onBegin?.call();

      bufferSource.start(0, start ?? 0);

      return () async {
        bufferSource.stop();
      };
    } catch (err, st) {
      print(err);
      print(st);
      throw Exception("Error playing buffer : $err \n $st");
    }
  }

  @override
  Future<Uint8List> load(String path,
      {AudioSource source = AudioSource.File,
      String? package,
      Function? onBegin,
      int sampleRate = 16000}) async {
    if (source == AudioSource.File) {
      throw Exception("Cannot specify files on web");
    }
    late ByteData data;
    print("Loading from path $path with package $package");
    try {
      if (package != null) {
        data = await rootBundle.load("packages/$package/$path");
      } else {
        data = await rootBundle.load(path);
      }
    } catch (err, st) {
      throw Exception("Error preloading audio from path $path: $err\n$st");
    }
    return data.buffer.asUint8List(data.offsetInBytes);
  }

  @override
  Future<Uint8List> decode(Uint8List encoded,
      {String extension = "opus"}) async {
    return encoded;
  }

  @override
  Future<CancelPlayback> playStream(
      Stream<Uint8List> data, int frequency, bool stereo,
      {void Function()? onComplete}) async {

    context = w.AudioContext(w.AudioContextOptions(sampleRate: frequency));

    try {
      final int bufferSize = 4096; // Common buffer size
      final int channels = stereo ? 2 : 1;

      final scriptNode = context.createScriptProcessor(bufferSize, 0, channels);

      // Buffer to store incoming audio data
      final List<double> audioQueue = [];
      bool isStreamComplete = false;

      // Listen to the stream and convert data to audio samples
      late StreamSubscription<Uint8List> streamSubscription;
      streamSubscription = data.listen(
        (Uint8List chunk) {
          // Convert Uint8List to Float32 samples (assuming PCM16 format)
          final samples =
              chunk.buffer.asInt16List().map((sample) => sample / 32768.0);
          audioQueue.addAll(samples);
        },
        onDone: () {
          isStreamComplete = true;
          streamSubscription.cancel();
        },
        onError: (error) {
          print('Stream error: $error');
          streamSubscription.cancel();
          onComplete?.call();
        },
      );

      // Set up the audio processing callback
      scriptNode.onaudioprocess = ((w.AudioProcessingEvent event) {
        final outputBuffer = event.outputBuffer;
        final int framesToProcess = outputBuffer.length;

        for (int channel = 0; channel < channels; channel++) {
          final channelData = Float32List(framesToProcess);

          // Fill the channel data from our queue
          for (int i = 0; i < framesToProcess; i++) {
            if (audioQueue.isNotEmpty) {
              channelData[i] = audioQueue.removeAt(0);
            } else {
              channelData[i] = 0.0; // Silence if no data available
            }
          }

          // Copy data to the output buffer
          outputBuffer.copyToChannel(channelData.toJS, channel);
        }

        // Check if stream is complete and queue is empty
        if (isStreamComplete && audioQueue.isEmpty) {
          scriptNode.disconnect();
          onComplete?.call();
        }
      }).toJS;

      // Connect the script processor to the audio context destination
      scriptNode.connect(context.destination);

      return () async {
        scriptNode.disconnect();
      };
    } catch (err, st) {
      print('Error in playStream: $err');
      print('Stack trace: $st');
      throw Exception("Error playing stream: $err\n$st");
    }
  }

  @override
  Future<Duration> getDuration(Uint8List data, AudioEncoding encoding) {
    // TODO: implement getDuration
    throw UnimplementedError();
  }
}

class CrossPlatformAudioWebPlugin extends CrossPlatformAudioPlatform {
  late AudioService _webAudioService;
  @override
  AudioService get service => _webAudioService;

  static void registerWith(Registrar registrar) {
    final plugin = CrossPlatformAudioWebPlugin();
    plugin._webAudioService = WebAudioService();
    CrossPlatformAudioPlatform.instance = plugin;
  }
}
