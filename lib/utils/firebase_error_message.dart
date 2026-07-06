import 'package:firebase_core/firebase_core.dart';

String describeFirebaseError(
  Object error, {
  String permissionDeniedMessage =
      '権限がありません。Firebase のルール反映後に再試行するか、再ログインしてください。',
}) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' ||
      'unauthorized' =>
        '$permissionDeniedMessage（${error.plugin}/$error.code）',
      'unavailable' => 'Firebase に接続できません。時間をおいて再試行してください。',
      _ => error.message ?? '${error.plugin}/${error.code}',
    };
  }
  return error.toString();
}
