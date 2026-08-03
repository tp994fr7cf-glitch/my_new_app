/// Resolves board time on the same Agora NTP-based wall clock used by recording.
///
/// The monotonic elapsed clock extends the sampled NTP anchor so ordinary
/// device-clock corrections cannot move board time backward or forward. Local
/// wall time is only a fallback when Agora NTP is unavailable. This is the
/// current verified baseline, not a prohibition on evidence-based fixes.
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
