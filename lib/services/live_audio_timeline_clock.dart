import 'dart:async';

const int liveAudioMaximumNtpSkewMs = 10000;
const int liveAudioMaximumStableNtpAnchorSkewMs = 100;

class LiveAudioNtpSyncResult {
  const LiveAudioNtpSyncResult({
    required this.confirmed,
    required this.attempts,
    required this.rejectedSamples,
    this.anchorMs,
    this.anchorElapsedUs,
  });

  final bool confirmed;
  final int attempts;
  final int rejectedSamples;
  final int? anchorMs;
  final int? anchorElapsedUs;
}

/// Rejects positive but not-yet-synchronized Agora NTP samples.
///
/// Some Android RTC starts can briefly return a positive value that is not an
/// epoch wall time. Comparing it with the trusted Functions server anchor keeps
/// that value from pinning every board event to zero seconds.
bool isPlausibleLiveAudioNtpSample({
  required int ntpWallTimeMs,
  required int sampleElapsedUs,
  required int trustedAnchorMs,
  required int trustedAnchorElapsedUs,
  int maximumSkewMs = liveAudioMaximumNtpSkewMs,
}) {
  if (ntpWallTimeMs <= 0 ||
      sampleElapsedUs < 0 ||
      trustedAnchorMs <= 0 ||
      trustedAnchorElapsedUs < 0 ||
      sampleElapsedUs < trustedAnchorElapsedUs ||
      maximumSkewMs < 0) {
    return false;
  }
  final projectedTrustedWallTimeMs =
      trustedAnchorMs + (sampleElapsedUs - trustedAnchorElapsedUs) / 1000;
  return (ntpWallTimeMs - projectedTrustedWallTimeMs).abs() <= maximumSkewMs;
}

/// Waits for consecutive stable Agora NTP samples before shared timeline input
/// is enabled.
///
/// A plausible sample is not enough on a cold RTC start because Agora can
/// briefly move from an unsynchronized value to its real NTP clock. Comparing
/// each sample's projected monotonic anchor prevents accepting that transition.
///
/// Keep this as a multi-sample confirmation. On 2026-08-04, production Android
/// data showed the first part's board clock about 0.58 seconds behind the Agora
/// audio clock when its first unsynchronized NTP value was rejected and the
/// one-shot Functions clock fallback remained in use. That was perceived as an
/// approximately one-second audio/board offset. A single plausible sample or a
/// silent fallback would make that first-part-only failure intermittent again.
Future<LiveAudioNtpSyncResult> confirmLiveAudioNtpClock({
  required Future<int?> Function() sampleNtpWallTimeMs,
  required int Function() currentElapsedUs,
  required int trustedAnchorMs,
  required int trustedAnchorElapsedUs,
  bool Function()? isCancelled,
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 250),
  int requiredStableSamples = 3,
  int maximumSkewMs = liveAudioMaximumNtpSkewMs,
  int maximumStableAnchorSkewMs = liveAudioMaximumStableNtpAnchorSkewMs,
}) async {
  if (timeout < Duration.zero ||
      pollInterval < Duration.zero ||
      requiredStableSamples <= 0 ||
      maximumStableAnchorSkewMs < 0) {
    throw ArgumentError('Invalid live audio NTP synchronization settings.');
  }

  final stopwatch = Stopwatch()..start();
  int? previousCandidateAnchorUs;
  var stableSamples = 0;
  var attempts = 0;
  var rejectedSamples = 0;

  while (isCancelled?.call() != true) {
    final sampleStartedUs = currentElapsedUs();
    final ntpWallTimeMs = await sampleNtpWallTimeMs();
    final sampleFinishedUs = currentElapsedUs();
    final sampleElapsedUs = (sampleStartedUs + sampleFinishedUs) ~/ 2;
    attempts++;

    final plausible =
        ntpWallTimeMs != null &&
        isPlausibleLiveAudioNtpSample(
          ntpWallTimeMs: ntpWallTimeMs,
          sampleElapsedUs: sampleElapsedUs,
          trustedAnchorMs: trustedAnchorMs,
          trustedAnchorElapsedUs: trustedAnchorElapsedUs,
          maximumSkewMs: maximumSkewMs,
        );
    if (plausible) {
      final candidateAnchorUs =
          ntpWallTimeMs * Duration.microsecondsPerMillisecond - sampleElapsedUs;
      final previousAnchorUs = previousCandidateAnchorUs;
      if (previousAnchorUs == null ||
          (candidateAnchorUs - previousAnchorUs).abs() <=
              maximumStableAnchorSkewMs * Duration.microsecondsPerMillisecond) {
        stableSamples++;
      } else {
        stableSamples = 1;
      }
      previousCandidateAnchorUs = candidateAnchorUs;
      if (stableSamples >= requiredStableSamples) {
        return LiveAudioNtpSyncResult(
          confirmed: true,
          attempts: attempts,
          rejectedSamples: rejectedSamples,
          anchorMs: ntpWallTimeMs,
          anchorElapsedUs: sampleElapsedUs,
        );
      }
    } else {
      rejectedSamples++;
      stableSamples = 0;
      previousCandidateAnchorUs = null;
    }

    if (stopwatch.elapsed >= timeout) {
      break;
    }
    await Future<void>.delayed(pollInterval);
  }

  return LiveAudioNtpSyncResult(
    confirmed: false,
    attempts: attempts,
    rejectedSamples: rejectedSamples,
  );
}

bool canEmitLiveAudioTimelineEvents({
  required bool canPublish,
  required bool sessionIsActive,
  required bool ntpClockConfirmed,
}) {
  return canPublish && sessionIsActive && ntpClockConfirmed;
}

/// Resolves board time on the same Agora NTP-based wall clock used by recording.
///
/// The monotonic elapsed clock extends the sampled NTP anchor so ordinary
/// device-clock corrections cannot move board time backward or forward. Local
/// wall time is only a fallback when no synchronized anchor is available.
double resolveLiveAudioSessionElapsedSec({
  required int sessionStartedAtMs,
  required int localNowMs,
  required int currentElapsedUs,
  int? synchronizedAnchorMs,
  int? synchronizedAnchorElapsedUs,
}) {
  if (sessionStartedAtMs <= 0) {
    return currentElapsedUs <= 0 ? 0 : currentElapsedUs / 1000000;
  }
  final anchorMs = synchronizedAnchorMs;
  final anchorElapsedUs = synchronizedAnchorElapsedUs;
  final synchronizedNowMs =
      anchorMs != null &&
          anchorMs > 0 &&
          anchorElapsedUs != null &&
          anchorElapsedUs >= 0 &&
          currentElapsedUs >= anchorElapsedUs
      ? anchorMs + (currentElapsedUs - anchorElapsedUs) / 1000
      : localNowMs.toDouble();
  final elapsedMs = synchronizedNowMs - sessionStartedAtMs;
  return elapsedMs <= 0 ? 0 : elapsedMs / 1000;
}
