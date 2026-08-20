@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_audio_recording_service_io.dart';

void main() {
  test('record-while-writing capture does not enable call-style voice processing', () {
    expect(lessonAudioRecordConfig.autoGain, isFalse);
    expect(lessonAudioRecordConfig.echoCancel, isFalse);
    expect(lessonAudioRecordConfig.noiseSuppress, isFalse);
  });
}
