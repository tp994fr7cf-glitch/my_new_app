class LessonMediaFilePickerException implements Exception {
  const LessonMediaFilePickerException(this.message);

  final String message;

  @override
  String toString() => message;
}
