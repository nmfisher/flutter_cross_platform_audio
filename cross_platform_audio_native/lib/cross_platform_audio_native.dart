import 'package:cross_platform_audio_platform_interface/cross_platform_audio_platform_interface.dart';
import 'native_audio_service.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';

class CrossPlatformAudioNativePlugin extends CrossPlatformAudioPlatform {
  
  late final AudioService _service;
  
  @override
  get service => _service;

  CrossPlatformAudioNativePlugin() {
    _service = NativeAudioService();
  }

  static void registerWith() {
    CrossPlatformAudioPlatform.instance = CrossPlatformAudioNativePlugin();
  }
}
