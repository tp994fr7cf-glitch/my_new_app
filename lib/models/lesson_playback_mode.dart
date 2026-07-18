enum LessonPlaybackMode {
  continuous,
  independentSingle,
  independentPanels;

  static LessonPlaybackMode fromStorage(String? value) {
    return switch (value) {
      'independentSingle' => LessonPlaybackMode.independentSingle,
      'independentPanels' => LessonPlaybackMode.independentPanels,
      _ => LessonPlaybackMode.continuous,
    };
  }

  String toStorage() {
    return switch (this) {
      LessonPlaybackMode.continuous => 'continuous',
      LessonPlaybackMode.independentSingle => 'independentSingle',
      LessonPlaybackMode.independentPanels => 'independentPanels',
    };
  }

  String get displayLabel {
    return switch (this) {
      LessonPlaybackMode.continuous => '一貫再生',
      LessonPlaybackMode.independentSingle => '独立再生（単一画面）',
      LessonPlaybackMode.independentPanels => '独立再生（独立画面）',
    };
  }

  bool get isIndependent => this != LessonPlaybackMode.continuous;
}
