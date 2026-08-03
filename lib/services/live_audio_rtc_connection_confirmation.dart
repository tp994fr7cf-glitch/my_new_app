import 'dart:async';

typedef LiveAudioRtcConnectedProbe = Future<bool> Function();

Future<void> confirmLiveAudioRtcConnection({
  required Future<void> joinCommand,
  required Future<void> callbackSignal,
  required LiveAudioRtcConnectedProbe isConnected,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 250),
  Duration probeTimeout = const Duration(seconds: 2),
}) async {
  var callbackCompleted = false;
  Object? commandError;
  StackTrace? commandStackTrace;

  unawaited(
    callbackSignal.then<void>((_) {
      callbackCompleted = true;
    }),
  );
  unawaited(
    joinCommand.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        commandError = error;
        commandStackTrace = stackTrace;
      },
    ),
  );

  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (commandError case final error?) {
      Error.throwWithStackTrace(error, commandStackTrace ?? StackTrace.current);
    }
    if (callbackCompleted) {
      return;
    }
    try {
      if (await isConnected().timeout(probeTimeout)) {
        return;
      }
    } catch (_) {
      // The next probe or Agora callback can still confirm the connection.
    }
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      break;
    }
    await Future<void>.delayed(
      remaining < pollInterval ? remaining : pollInterval,
    );
  }

  if (commandError case final error?) {
    Error.throwWithStackTrace(error, commandStackTrace ?? StackTrace.current);
  }
  throw TimeoutException('Agoraの接続完了を確認できませんでした。', timeout);
}
