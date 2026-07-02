import 'package:firebase_storage/firebase_storage.dart';

UploadTask putPlatformFile(
  Reference ref,
  String path,
  SettableMetadata metadata,
) {
  throw UnsupportedError('putFile is not supported on this platform.');
}
