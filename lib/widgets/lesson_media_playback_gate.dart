/// Ensures only one lesson-management preview player runs at a time.
class LessonMediaPlaybackGate {
  String? _activeOwnerId;
  final Map<String, Future<void> Function()> _pauseByOwnerId = {};

  void register({
    required String ownerId,
    required Future<void> Function() pause,
  }) {
    final trimmed = ownerId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _pauseByOwnerId[trimmed] = pause;
  }

  void unregister(String ownerId) {
    final trimmed = ownerId.trim();
    _pauseByOwnerId.remove(trimmed);
    if (_activeOwnerId == trimmed) {
      _activeOwnerId = null;
    }
  }

  Future<void> claim(String ownerId) async {
    final trimmed = ownerId.trim();
    if (trimmed.isEmpty || _activeOwnerId == trimmed) {
      return;
    }
    final previousId = _activeOwnerId;
    _activeOwnerId = trimmed;
    final pause = previousId == null ? null : _pauseByOwnerId[previousId];
    await pause?.call();
  }
}
