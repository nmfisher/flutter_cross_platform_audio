import 'dart:async';
import 'dart:typed_data';

import 'package:cross_platform_audio_platform_interface/cross_platform_audio_platform_interface.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';

class CrossPlatformAudioService extends AudioService {

  @override
  void dispose() {
    CrossPlatformAudioPlatform.instance.service.dispose();
  }

  @override
  Future initialize() {
    return CrossPlatformAudioPlatform.instance.service.initialize();
  }

  Future<Duration> getDuration(Uint8List data, AudioEncoding encoding) { 
    return CrossPlatformAudioPlatform.instance.service.getDuration(data, encoding);
  }

  @override
  Future play(String path,
      {AudioSource source = AudioSource.File,
      String? package,
      void Function()? onBegin,
      void Function()? onComplete,
      int sampleRate = 16000,
      double speed = 1.0}) {
    return CrossPlatformAudioPlatform.instance.service.play(path, source:source, package: package, sampleRate: sampleRate, speed: speed, onBegin: onBegin, onComplete: onComplete);
  }

  @override
  Future<void Function()> playBuffer(Uint8List data, {void Function()? onBegin, void Function()? onComplete, AudioEncoding encoding=AudioEncoding.PCM16, int? sampleRate, bool? stereo, double? start}) {
    return CrossPlatformAudioPlatform.instance.service.playBuffer(data, sampleRate:sampleRate, stereo:stereo, onBegin:onBegin, onComplete: onComplete, encoding: encoding, start: start);
  }

  
  @override
  Future<Uint8List> load(String path, {AudioSource source = AudioSource.File, String? package, Function? onBegin, int sampleRate = 16000}) {
    return CrossPlatformAudioPlatform.instance.service.load(path, source:source, package: package, onBegin: onBegin, sampleRate: sampleRate);
  }
  
  @override
  Future<Uint8List> decode(Uint8List encoded, {String extension = "opus"}) {
    return CrossPlatformAudioPlatform.instance.service.decode(encoded, extension:extension);
  }
  
  @override
  Future playStream(Stream<Uint8List> data, int frequency, bool stereo, {void Function()? onComplete}) {
    return CrossPlatformAudioPlatform.instance.service.playStream(data, frequency, stereo, onComplete: onComplete); 
  }

}
