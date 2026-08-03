class LiveAudioSnapshotTracker {
  int _changeGeneration = 0;
  int _savedGeneration = 0;
  int _serverRevision = 0;

  bool get hasUnsavedChanges => _changeGeneration > _savedGeneration;
  int get changeGeneration => _changeGeneration;
  int get serverRevision => _serverRevision;

  bool shouldApplyServerSnapshot({
    required int revision,
    required bool preserveUnsavedLocalChanges,
  }) {
    return revision >= _serverRevision &&
        (!preserveUnsavedLocalChanges || !hasUnsavedChanges);
  }

  void markChanged() {
    _changeGeneration++;
  }

  void observeServerRevision(int revision) {
    if (revision > _serverRevision) {
      _serverRevision = revision;
    }
  }

  void markSaved({required int generation, required int revision}) {
    if (generation > _savedGeneration) {
      _savedGeneration = generation;
    }
    observeServerRevision(revision);
  }

  void reset({int serverRevision = 0}) {
    _changeGeneration = 0;
    _savedGeneration = 0;
    _serverRevision = serverRevision;
  }
}
