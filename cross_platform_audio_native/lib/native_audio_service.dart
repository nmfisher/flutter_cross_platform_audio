import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as sl;
import 'package:logging/logging.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:opusfile_dart/opusfile_dart.dart';
import 'package:wave_builder/wave_builder.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

import 'streaming/streaming.dart';

class NativeAudioService extends AudioService {
  final _decoder = OpusFileDecoder();

  final _logger = Logger("NativeAudioService");

  @override
  Future initialize() async {
    await sl.SoLoud.instance.init();
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
    /// Initialize the stream to reflect the requested PCM data format.
    final currentSound = sl.SoLoud.instance.setBufferStream(
      maxBufferSize: 1024 * 1024 * 10, // 10 MB
      sampleRate: frequency,
      channels: stereo ? sl.Channels.stereo : sl.Channels.mono,
      pcmFormat: sl.BufferPcmType.s16le,
      onBuffering: (_, __, ___) async {},
    );

    int totalSamples = 0;
    late StreamSubscription listener;

    late DateTime startTime;

    bool wasCancelled = false;

    listener = data.listen((d) async {
      if (wasCancelled) {
        return;
      }
      try {
        sl.SoLoud.instance.addAudioDataStreamU8(currentSound, d);
      } on sl.SoLoudPcmBufferFullOrStreamEndedCppException {
        _logger.severe('pcm buffer full or stream already set '
            'to be ended');
      } catch (e) {
        _logger.severe(e);
      }

      /// If this is the first chunk, start the audio.
      if (totalSamples == 0) {
        await sl.SoLoud.instance.play(currentSound);
      }

      totalSamples += d.length ~/
          (stereo ? 4 : 2); // 2 bytes per sample, 2 channels if stereo


    }, onDone: () async {
      await listener.cancel();
      sl.SoLoud.instance.setDataIsEnded(currentSound);
      if (wasCancelled) {
        return;
      }
      var duration = ((totalSamples / frequency) * 1000).toInt();
      var elapsed = DateTime.now().millisecondsSinceEpoch -
          startTime.millisecondsSinceEpoch;

      _logger.info("Estimated audio duration: ${duration}ms, elapsed ${elapsed}");
      if (duration > elapsed) {
        _logger.info("Waiting for ${duration - elapsed}");
        await Future.delayed(Duration(milliseconds: duration - elapsed));
      }

      if (wasCancelled) {
        return;
      }

      onComplete?.call();
    }, onError: (err) async {
      _logger.severe(err);
      sl.SoLoud.instance.setDataIsEnded(currentSound);
      onComplete?.call();
    });

    startTime = DateTime.now();

    return () async {
      wasCancelled = true;
      await listener.cancel();
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
