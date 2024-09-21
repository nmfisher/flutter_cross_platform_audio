import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';

abstract class CrossPlatformAudioPlatform extends PlatformInterface {
  CrossPlatformAudioPlatform() : super(token: _token);

  static final Object _token = Object();

  AudioService get service;
  static late CrossPlatformAudioPlatform _instance;
  static CrossPlatformAudioPlatform get instance => _instance;

  static set instance(CrossPlatformAudioPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }
}
