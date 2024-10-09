import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:opusfile_dart/opusfile_dart.dart';
import 'package:wave_builder/wave_builder.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

import 'streaming/streaming.dart';

class NativeAudioService extends AudioService {
  final _decoder = OpusFileDecoder();
  final _channel =
      const MethodChannel("com.nick-fisher.cross_platform_audio_native");

  Logger get log => Logger(this.runtimeType.toString());

  Future initialize() async {
    // noop
  }

  void dispose() {}

  Future<Duration> getDuration(Uint8List data, AudioEncoding encoding) async {
    if (!encoding.isPCM) {
      throw UnsupportedError('Only PCM encodings are currently supported');
    }

    final int sampleRate =
        encoding.sampleRate ?? 44100; // Default to 44.1kHz if not specified
    final int channels = 2; // Assuming stereo audio, adjust if needed

    int bytesPerSample = encoding.bitsPerSample! ~/ 8;

    final int totalSamples = data.length ~/ (bytesPerSample * channels);
    final double durationInSeconds = totalSamples / sampleRate;

    return Duration(microseconds: (durationInSeconds * 1000000).round());
  }

  ///
  /// Plays the audio located at the specified [path] (interpreted as either a file or asset path, depending on [source])
  ///
  @override
  Future<CancelPlayback> play(
    String path, {
    AudioSource source = AudioSource.File,
    String? package,
    Function? onBegin,
    Function? onComplete,
    int sampleRate = 16000,
    double speed = 1.0,
  }) async {
    var player = ja.AudioPlayer();
    await player.setAudioSource(
        source == AudioSource.File
            ? ja.AudioSource.file(path)
            : ja.AudioSource.asset(path, package: package),
        preload: true);
    late StreamSubscription listener;
    listener = player.playerStateStream.listen((state) {
      if (state.processingState == ja.ProcessingState.ready) {
        onBegin?.call();
      } else if (state.processingState == ja.ProcessingState.completed) {
        onComplete?.call();
        listener.cancel();
      }
    });
    await player.play();
    return () async {
      await player.stop();
    };
  }

  Future<CancelPlayback> playBuffer(Uint8List data,
      {void Function()? onComplete,
      void Function()? onBegin,
      AudioEncoding encoding = const PCM16(sampleRate: 16000),
      int? sampleRate,
      bool? stereo,
      double? start}) async {
    switch (encoding) {
      case OPUS():
        var decoded = await OpusFileDecoder().decode(data);
        data = decoded.buffer.asUint8List(decoded.offsetInBytes);
      case PCM16():
        if (stereo == null || sampleRate == null) {
          throw Exception(
              "stereo and sampleRate must be provided for PCM data");
        }
        var waveBuilder = WaveBuilder(frequency: sampleRate, stereo: stereo);
        waveBuilder.appendFileContents(data);
        data = Uint8List.fromList(waveBuilder.fileBytes);
      case PCMF32():
        if (stereo == null || sampleRate == null) {
          throw Exception(
              "stereo and sampleRate must be provided for PCM data");
        }
        data = Int16List.fromList(data.buffer
                .asFloat32List()
                .map((x) => (x * 32768).toInt())
                .toList())
            .buffer
            .asUint8List();
        var waveBuilder = WaveBuilder(frequency: sampleRate, stereo: stereo);
        waveBuilder.appendFileContents(data);
        data = Uint8List.fromList(waveBuilder.fileBytes);
      default:
        throw Exception("Unrecognied audio format");
    }

    late Future Function() canceller;

    if (Platform.isMacOS) {
      bool hasBegun = false;
      var player = ap.AudioPlayer();
      late StreamSubscription listener;
      listener = player.onPlayerStateChanged.listen((playerState) {
        if (playerState == ap.PlayerState.completed) {
          onComplete?.call();
          listener.cancel();
        } else if (playerState == ap.PlayerState.playing && !hasBegun) {
          onBegin?.call();
          hasBegun = true;
        }
      });
      await player.setSourceBytes(data, mimeType: "audio/wav");
      await player.seek(Duration.zero);
      if (start != null) {
        var duration = await player.getDuration();
        await player.seek(Duration(milliseconds: (start * 1000).toInt()));
      }
      await player.resume();
      canceller = () async {
        player.stop();
      };
    } else {
      var source = AudioBufferSource(data);
      var player = ja.AudioPlayer();

      late StreamSubscription _listener;
      bool hasBegun = false;

      _listener = player.playerStateStream.listen((state) {
        if (state.processingState == ja.ProcessingState.completed) {
          _listener.cancel();
          onComplete?.call();
        } else if (state.processingState == ja.ProcessingState.loading &&
            !hasBegun) {
          onBegin?.call();
          hasBegun = true;
        }
      });

      await player.setAudioSource(source, preload: false);
      await player.seek(Duration.zero);
      if (start != null) {
        var duration = await player.duration;
        if (duration == null) {
          throw Exception(
              "Failed to get duration, cannot specify start offset");
        }
        await player.seek(Duration(milliseconds: (start * 1000).toInt()));
      }

      await player.load();

      canceller = () async {
        player.stop();
      };
      player.play();
    }
    return canceller;
  }

  @override
  Future<CancelPlayback> playStream(
      Stream<Uint8List> data, int frequency, bool stereo,
      {void Function()? onComplete}) async {
    await _channel.invokeMethod("initializeAudioPlayer",
        {"sampleRate": frequency, "channels": stereo ? 2 : 1});

    int totalSamples = 0;
    late StreamSubscription listener;

    late DateTime startTime;

    listener = data.listen((d) async {
      await _channel.invokeMethod("addAudioData", {"audioData": d});
      totalSamples += d.length ~/
          (stereo ? 4 : 2); // 2 bytes per sample, 2 channels if stereo
    }, onDone: () async {
      var duration = ((totalSamples / frequency) * 1000).toInt();
      var elapsed = DateTime.now().millisecondsSinceEpoch -
          startTime.millisecondsSinceEpoch;

      print(
          "Estimated audio duration: ${duration}ms, elapsed ${elapsed}");
      if (duration > elapsed) {
        print("Waiting for ${duration - elapsed}");
        await Future.delayed(Duration(milliseconds: duration - elapsed));
      }

      await _channel.invokeMethod("streamComplete");
      await _channel.invokeMethod("stopPlayback");
      await _channel.invokeMethod("destroyAudioPlayer");
      onComplete?.call();
      print("COMPLETE");
    }, onError: (obj) async {
      await _channel.invokeMethod("stopPlayback");
      await _channel.invokeMethod("destroyAudioPlayer");
      onComplete?.call();
    });

    await _channel.invokeMethod("startPlayback");
    startTime = DateTime.now();

    return () async {
      await listener.cancel();
      await _channel.invokeMethod("stopPlayback");
      await _channel.invokeMethod("destroyAudioPlayer");
      onComplete?.call();
    };
  }

  @override
  Future<Uint8List> load(String path,
      {AudioSource source = AudioSource.File,
      String? package,
      Function? onBegin,
      int sampleRate = 16000}) async {
    late Uint8List encoded;

    if (source == AudioSource.Asset) {
      var buffer = await rootBundle
          .load(package == null ? path : "packages/$package/$path");
      encoded = buffer.buffer.asUint8List(buffer.offsetInBytes);
    } else {
      encoded = File(path).readAsBytesSync();
    }
    return encoded;
  }

  Future<Uint8List> decode(Uint8List encoded,
      {String extension = "opus"}) async {
    var decoded = _decoder.decode(encoded);
    return decoded.buffer.asUint8List(decoded.offsetInBytes);
  }
}
