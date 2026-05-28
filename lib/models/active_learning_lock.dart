enum ActiveLearningLockDecisionReason {
  noExistingLock,
  sameDevice,
  staleLock,
  blockedByOtherDevice,
}

class ActiveLearningLockSnapshot {
  const ActiveLearningLockSnapshot({
    required this.deviceId,
    required this.status,
    required this.lastHeartbeatAt,
  });

  final String? deviceId;
  final String? status;
  final DateTime? lastHeartbeatAt;
}

class ActiveLearningLockDecision {
  const ActiveLearningLockDecision({
    required this.canAcquire,
    required this.reason,
  });

  final bool canAcquire;
  final ActiveLearningLockDecisionReason reason;
}

ActiveLearningLockDecision decideActiveLearningLock({
  required ActiveLearningLockSnapshot? existingLock,
  required String currentDeviceId,
  required DateTime now,
  required Duration staleAfter,
}) {
  if (existingLock == null || existingLock.status != 'active') {
    return const ActiveLearningLockDecision(
      canAcquire: true,
      reason: ActiveLearningLockDecisionReason.noExistingLock,
    );
  }

  if (existingLock.deviceId == currentDeviceId) {
    return const ActiveLearningLockDecision(
      canAcquire: true,
      reason: ActiveLearningLockDecisionReason.sameDevice,
    );
  }

  final lastHeartbeatAt = existingLock.lastHeartbeatAt;
  final elapsedSinceHeartbeat = lastHeartbeatAt == null
      ? null
      : now.difference(lastHeartbeatAt);
  if (elapsedSinceHeartbeat == null ||
      (!elapsedSinceHeartbeat.isNegative &&
          elapsedSinceHeartbeat >= staleAfter)) {
    return const ActiveLearningLockDecision(
      canAcquire: true,
      reason: ActiveLearningLockDecisionReason.staleLock,
    );
  }

  return const ActiveLearningLockDecision(
    canAcquire: false,
    reason: ActiveLearningLockDecisionReason.blockedByOtherDevice,
  );
}
