import 'live_audio_probe_service.dart';

const maxLiveAudioPermissionApplyFollowUps = 3;

bool shouldFollowUpLiveAudioPermissionApply({
  required LiveAudioProbePermission? localPermission,
  required LiveAudioProbePermission? remotePermission,
  required int followUpCount,
  int maxFollowUps = maxLiveAudioPermissionApplyFollowUps,
}) {
  if (followUpCount >= maxFollowUps) {
    return false;
  }
  return remotePermission != null && remotePermission != localPermission;
}
