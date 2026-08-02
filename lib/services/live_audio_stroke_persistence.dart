Future<void> persistLiveAudioStrokeInOrder({
  required bool boardExistsOnServer,
  required Future<void> Function() saveBoardSnapshot,
  required Future<void> Function() saveStroke,
}) async {
  if (!boardExistsOnServer) {
    await saveBoardSnapshot();
  }
  await saveStroke();
}
