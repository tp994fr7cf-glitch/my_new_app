class LiveAudioSnapshotTracker {
  int _changeGeneration = 0;
  int _savedGeneration = 0;
  // Used when saving so an older server revision cannot overwrite newer data.
  int _serverRevision = 0;
  // Kept separately so unrelated updates at the same revision do not replace
  // board changes that have already arrived over RTC.
  int? _appliedServerRevision;

  bool get hasUnsavedChanges => _changeGeneration > _savedGeneration;
  int get changeGeneration => _changeGeneration;
  int get serverRevision => _serverRevision;

  bool shouldApplyServerSnapshot({
    required int revision,
    required bool preserveUnsavedLocalChanges,
  }) {
    return revision >= _serverRevision &&
        (_appliedServerRevision == null ||
            revision > _appliedServerRevision!) &&
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

  void markServerSnapshotApplied(int revision) {
    observeServerRevision(revision);
    if (_appliedServerRevision == null || revision > _appliedServerRevision!) {
      _appliedServerRevision = revision;
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
    _appliedServerRevision = null;
  }
}
