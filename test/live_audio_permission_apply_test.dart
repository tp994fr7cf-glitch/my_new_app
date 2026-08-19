import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/services/live_audio_permission_apply.dart';
import 'package:my_new_app/services/live_audio_probe_service.dart';

void main() {
  test('follows up when Firestore permission moved during an apply', () {
    expect(
      shouldFollowUpLiveAudioPermissionApply(
        localPermission: LiveAudioProbePermission.publisher,
        remotePermission: LiveAudioProbePermission.subscriber,
        followUpCount: 0,
      ),
      isTrue,
    );
  });

  test('does not follow up when local and remote permissions match', () {
    expect(
      shouldFollowUpLiveAudioPermissionApply(
        localPermission: LiveAudioProbePermission.publisher,
        remotePermission: LiveAudioProbePermission.publisher,
        followUpCount: 0,
      ),
      isFalse,
    );
  });

  test('stops following up after the retry limit', () {
    expect(
      shouldFollowUpLiveAudioPermissionApply(
        localPermission: LiveAudioProbePermission.subscriber,
        remotePermission: LiveAudioProbePermission.publisher,
        followUpCount: maxLiveAudioPermissionApplyFollowUps,
      ),
      isFalse,
    );
  });
}
