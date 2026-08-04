import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? lessonMaterialFileImageProvider(String filePath) =>
    FileImage(File(filePath));
