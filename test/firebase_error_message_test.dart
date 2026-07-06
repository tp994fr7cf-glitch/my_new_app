import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/utils/firebase_error_message.dart';

void main() {
  test('describeFirebaseError maps storage unauthorized', () {
    final message = describeFirebaseError(
      FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
        message: 'User is not authorized to perform the desired action.',
      ),
    );

    expect(message, contains('権限がありません'));
    expect(message, contains('firebase_storage/unauthorized'));
  });
}
