import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/lesson_media_storage_service.dart';

void main() {
  const service = LessonMediaStorageService();

  test('lesson media limit is 100MB', () {
    expect(LessonMediaStorageService.maxBytes, 100 * 1024 * 1024);
  });

  test('contentTypeForExtension returns expected mime types', () {
    expect(service.contentTypeForExtension('mp3'), 'audio/mpeg');
    expect(service.contentTypeForExtension('m4a'), 'audio/mp4');
    expect(service.contentTypeForExtension('mp4'), 'video/mp4');
  });

  test('allowedExtensionsForMediaType separates audio and video', () {
    expect(service.allowedExtensionsForMediaType('audio'), contains('mp3'));
    expect(service.allowedExtensionsForMediaType('video'), contains('mp4'));
  });

  test('storagePath builds course lesson segment path', () {
    expect(
      service.storagePath(
        courseId: 'course-1',
        lessonNumber: 2,
        segmentId: 'seg-abc',
        fileName: 'sample.mp3',
      ),
      'courseMedia/course-1/lessons/2/segments/seg-abc/sample.mp3',
    );
  });

  test('storagePath uses a stable lesson document id when provided', () {
    expect(
      service.storagePath(
        courseId: 'course-1',
        lessonId: 'lesson-stable-id',
        segmentId: 'seg-abc',
        fileName: 'sample.mp3',
      ),
      'courseMedia/course-1/lessons/lesson-stable-id/segments/seg-abc/sample.mp3',
    );
  });
}
