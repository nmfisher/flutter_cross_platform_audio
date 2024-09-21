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

class AudioBufferSource extends ja.StreamAudioSource {
  final Uint8List _buffer;

  AudioBufferSource(this._buffer) : super(tag: 'MyAudioSource');

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    // Returning the stream audio response with the parameters
    return ja.StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: (end ?? _buffer.length) - (start ?? 0),
      offset: start ?? 0,
      stream: Stream.fromIterable([_buffer.sublist(start ?? 0, end)]),
      contentType: 'audio/wav',
    );
  }
}

// just_audio buffer/streaming seems totally broken on macos
// don't use this!
class StreamingAudioBufferSource extends ja.StreamAudioSource {
  final _buffer = Uint8List(44100 * 60);
  int _writeOffset = 0;
  final _readOffset = 0;
  bool _completed = false;

  final Uint8List header;

  late final StreamSubscription _listener;

  StreamingAudioBufferSource(this.header, Stream<Uint8List> audio)
      : super(tag: 'MyAudioSource') {
    _buffer.setRange(0, header.length, header);
    _writeOffset += header.length;
    _listener = audio.listen((x) async {
      _buffer.setRange(_writeOffset, _writeOffset + x.length, x);
      _writeOffset += x.length;
    }, onDone: () async {
      _completed = true;
      await _listener.cancel();
    });
  }

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    print(
        "Requesting start $start end $end when write offset is $_writeOffset");
    // if (end != null) {
    // while (_completed == false) {
    //   print("Underflow, waiting..");
    //   await Future.delayed(Duration(seconds: 3));
    // }
    // }
    var contentLength = null;
    end ??= _writeOffset;
    // if (end == null) {
    //   contentLength = _writeOffset - (start ?? 0);
    // } else {
    contentLength = end! - start!;
    // }
    print("Returning sublist from $start to $end");
    // Returning the stream audio response with the parameters
    return ja.StreamAudioResponse(
      sourceLength: _completed ? _writeOffset : null,
      contentLength: contentLength,
      offset: start ?? 0,
      stream: Stream.fromIterable([_buffer.sublist(start ?? 0, end).toList()]),
      contentType: 'audio/wav',
    );
  }
}

class NativeAudioService extends AudioService {
  final _decoder = OpusFileDecoder();

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
  Future play(
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
  }

  Future<void Function()> playBuffer(Uint8List data,
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

    late void Function() canceller;

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
      canceller = () {
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

      canceller = () {
        player.stop();
      };
      player.play();
    }
    return canceller;
  }

  Future playStream(Stream<Uint8List> data, int frequency, bool stereo,
      {void Function()? onComplete}) async {
    var waveBuilder = WaveBuilder(frequency: frequency, stereo: stereo);
    // var header = Uint8List.fromList(waveBuilder.fileBytes);

    // var source = StreamingAudioBufferSource(header, data);
    // var player = ja.AudioPlayer();

    // await player.setAudioSource(source);
    // if (onComplete != null) {
    //   late StreamSubscription _listener;
    //   _listener = player.playerStateStream.listen((state) {
    //     if (state.processingState == ja.ProcessingState.buffering) {
    //       _listener.cancel();
    //       onComplete.call();
    //     }
    //   });
    // }
    // await player.play();
    throw Exception("FOO");
    // var converted = Uint8List.fromList(waveBuilder.fileBytes);
    // var player = ap.AudioPlayer();
    // await player.setSourceAsset(path) .setSourceBytes(Uint8List.fromList(waveBuilder.fileBytes), mimeType: "audio/wav");
    // await player.seek(Duration.zero);
    // await player.resume();
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
