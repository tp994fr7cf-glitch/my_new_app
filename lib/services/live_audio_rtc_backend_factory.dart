import 'package:flutter/foundation.dart';

import 'live_audio_rtc_backend.dart';
import 'live_audio_rtc_backend_agora.dart';
import 'live_audio_rtc_backend_android.dart';

LiveAudioRtcBackend createLiveAudioRtcBackend() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return LiveAudioAndroidRtcBackend();
  }
  return LiveAudioAgoraRtcBackend();
}
