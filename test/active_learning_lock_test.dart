import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/models/active_learning_lock.dart';

void main() {
  group('decideActiveLearningLock', () {
    const staleAfter = Duration(seconds: 45);
    final now = DateTime(2026, 5, 28, 9);

    test('allows a missing lock', () {
      final decision = decideActiveLearningLock(
        existingLock: null,
        currentDeviceId: 'device-a',
        now: now,
        staleAfter: staleAfter,
      );

      expect(decision.canAcquire, isTrue);
      expect(decision.reason, ActiveLearningLockDecisionReason.noExistingLock);
    });

    test('allows the same device to refresh its lock', () {
      final decision = decideActiveLearningLock(
        existingLock: ActiveLearningLockSnapshot(
          deviceId: 'device-a',
          status: 'active',
          lastHeartbeatAt: now.subtract(const Duration(seconds: 10)),
        ),
        currentDeviceId: 'device-a',
        now: now,
        staleAfter: staleAfter,
      );

      expect(decision.canAcquire, isTrue);
      expect(decision.reason, ActiveLearningLockDecisionReason.sameDevice);
    });

    test('allows an inactive lock from another device', () {
      final decision = decideActiveLearningLock(
        existingLock: ActiveLearningLockSnapshot(
          deviceId: 'device-b',
          status: 'inactive',
          lastHeartbeatAt: now.subtract(const Duration(seconds: 10)),
        ),
        currentDeviceId: 'device-a',
        now: now,
        staleAfter: staleAfter,
      );

      expect(decision.canAcquire, isTrue);
      expect(decision.reason, ActiveLearningLockDecisionReason.noExistingLock);
    });

    test('allows taking over a stale other-device lock', () {
      final decision = decideActiveLearningLock(
        existingLock: ActiveLearningLockSnapshot(
          deviceId: 'device-b',
          status: 'active',
          lastHeartbeatAt: now.subtract(const Duration(seconds: 60)),
        ),
        currentDeviceId: 'device-a',
        now: now,
        staleAfter: staleAfter,
      );

      expect(decision.canAcquire, isTrue);
      expect(decision.reason, ActiveLearningLockDecisionReason.staleLock);
    });

    test('blocks a fresh other-device lock', () {
      final decision = decideActiveLearningLock(
        existingLock: ActiveLearningLockSnapshot(
          deviceId: 'device-b',
          status: 'active',
          lastHeartbeatAt: now.subtract(const Duration(seconds: 10)),
        ),
        currentDeviceId: 'device-a',
        now: now,
        staleAfter: staleAfter,
      );

      expect(decision.canAcquire, isFalse);
      expect(
        decision.reason,
        ActiveLearningLockDecisionReason.blockedByOtherDevice,
      );
    });
  });
}
