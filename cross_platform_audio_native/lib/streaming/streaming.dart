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

class StreamingAudioSource extends ja.StreamAudioSource {
  final Stream<Uint8List> _stream;
  final String _contentType;
  final List<int> _buffer = [];
  int _bufferLength = 0;
  late final StreamSubscription<Uint8List> _subscription;
  final _controller = StreamController<List<int>>();

  StreamingAudioSource(this._stream, {String contentType = 'audio/mpeg'})
      : _contentType = contentType {
    _subscription = _stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _bufferLength += chunk.length;
        _controller.add(chunk);
      },
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    return ja.StreamAudioResponse(
      sourceLength: null, // Unknown total length
      contentLength: end! - start!,
      offset: start,
      stream: Stream.value(_buffer.sublist(start!, end!)),
      contentType: _contentType,
    );
  }
}