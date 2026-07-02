import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

UploadTask putPlatformFile(
  Reference ref,
  String path,
  SettableMetadata metadata,
) {
  return ref.putFile(File(path), metadata);
}
