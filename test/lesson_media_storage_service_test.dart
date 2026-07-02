import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_media_storage_service.dart';

void main() {
  const service = LessonMediaStorageService();

  test('contentTypeForExtension returns expected mime types', () {
    expect(service.contentTypeForExtension('mp3'), 'audio/mpeg');
    expect(service.contentTypeForExtension('m4a'), 'audio/mp4');
    expect(service.contentTypeForExtension('mp4'), 'video/mp4');
  });

  test('allowedExtensionsForMediaType separates audio and video', () {
    expect(service.allowedExtensionsForMediaType('audio'), contains('mp3'));
    expect(service.allowedExtensionsForMediaType('video'), contains('mp4'));
  });

  test('storagePath builds course lesson path', () {
    expect(
      service.storagePath(
        courseId: 'course-1',
        lessonNumber: 2,
        fileName: 'sample.mp3',
      ),
      'courseMedia/course-1/lessons/2/sample.mp3',
    );
  });
}
