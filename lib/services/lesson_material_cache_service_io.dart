import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/lesson_whiteboard_board_set.dart';
import 'lesson_material_cache_types.dart';

class LessonMaterialCacheService {
  LessonMaterialCacheService();

  static const int _manifestVersion = 1;
  final Map<String, _LessonMaterialManifest?> _manifestCache = {};

  bool get supported => Platform.isAndroid;

  Future<LessonMaterialCacheStatus> status({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return const LessonMaterialCacheStatus.unsupported();
    }
    final manifest = await _readManifest(
      courseId: courseId,
      lessonId: lessonId,
      refresh: true,
    );
    if (manifest == null) {
      return const LessonMaterialCacheStatus(
        supported: true,
        hasCurrentCache: false,
        hasStaleCache: false,
        totalBytes: 0,
      );
    }
    final expectedPaths = lessonMaterialStoragePaths(boardSet);
    final manifestPaths = manifest.files.keys.toList()..sort();
    final current =
        manifest.fingerprint == lessonMaterialFingerprint(boardSet) &&
        expectedPaths.join('\n') == manifestPaths.join('\n') &&
        await _allFilesExist(
          courseId: courseId,
          lessonId: lessonId,
          manifest: manifest,
        );
    return LessonMaterialCacheStatus(
      supported: true,
      hasCurrentCache: current,
      hasStaleCache: !current,
      totalBytes: manifest.totalBytes,
    );
  }

  Future<String?> localPath({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
    required String storagePath,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return null;
    }
    final manifest = await _readManifest(
      courseId: courseId,
      lessonId: lessonId,
    );
    if (manifest == null ||
        manifest.fingerprint != lessonMaterialFingerprint(boardSet)) {
      return null;
    }
    final fileName = manifest.files[storagePath];
    if (fileName == null) {
      return null;
    }
    final file = File(
      '${(await _lessonDirectory(courseId, lessonId)).path}'
      '${Platform.pathSeparator}files${Platform.pathSeparator}$fileName',
    );
    return await file.exists() ? file.path : null;
  }

  Future<void> downloadLesson({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
    required void Function(LessonMaterialDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return;
    }
    final storagePaths = lessonMaterialStoragePaths(boardSet);
    if (storagePaths.isEmpty) {
      await deleteLesson(courseId: courseId, lessonId: lessonId);
      return;
    }

    final active = await _lessonDirectory(courseId, lessonId);
    final parent = active.parent;
    await parent.create(recursive: true);
    await _cleanupInterruptedDirectories(active);
    final staging = Directory(
      '${active.path}.staging-${DateTime.now().microsecondsSinceEpoch}',
    );
    final filesDirectory = Directory(
      '${staging.path}${Platform.pathSeparator}files',
    );
    await filesDirectory.create(recursive: true);
    final files = <String, String>{};
    var totalBytes = 0;

    try {
      for (final entry in storagePaths.indexed) {
        if (isCancelled()) {
          throw const LessonMaterialCacheCancelled();
        }
        final storagePath = entry.$2;
        final fileName = _fileNameFor(storagePath);
        final destination = File(
          '${filesDirectory.path}${Platform.pathSeparator}$fileName',
        );
        final task = FirebaseStorage.instance
            .ref(storagePath)
            .writeToFile(destination);
        late final StreamSubscription<TaskSnapshot> subscription;
        subscription = task.snapshotEvents.listen((snapshot) {
          if (isCancelled()) {
            unawaited(task.cancel());
          }
          final currentFraction = snapshot.totalBytes <= 0
              ? 0.0
              : snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(
            LessonMaterialDownloadProgress(
              downloadedBytes:
                  (entry.$1 * 1000) + (currentFraction * 1000).round(),
              totalBytes: storagePaths.length * 1000,
              completedFiles: entry.$1,
              totalFiles: storagePaths.length,
            ),
          );
        });
        try {
          await task;
        } on FirebaseException catch (error) {
          if (isCancelled() || error.code == 'canceled') {
            throw const LessonMaterialCacheCancelled();
          }
          rethrow;
        } finally {
          await subscription.cancel();
        }
        if (isCancelled()) {
          throw const LessonMaterialCacheCancelled();
        }
        files[storagePath] = fileName;
        totalBytes += await destination.length();
        onProgress(
          LessonMaterialDownloadProgress(
            downloadedBytes: (entry.$1 + 1) * 1000,
            totalBytes: storagePaths.length * 1000,
            completedFiles: entry.$1 + 1,
            totalFiles: storagePaths.length,
          ),
        );
      }

      final manifest = _LessonMaterialManifest(
        fingerprint: lessonMaterialFingerprint(boardSet),
        files: files,
        totalBytes: totalBytes,
      );
      await File(
        '${staging.path}${Platform.pathSeparator}manifest.json',
      ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
      await _replaceDirectory(active: active, staging: staging);
      _manifestCache[_cacheKey(courseId, lessonId)] = manifest;
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> deleteLesson({
    required String courseId,
    required String lessonId,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return;
    }
    final directory = await _lessonDirectory(courseId, lessonId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _manifestCache.remove(_cacheKey(courseId, lessonId));
  }

  Future<void> deleteAll() async {
    if (!supported) {
      return;
    }
    final root = await _rootDirectory();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    _manifestCache.clear();
  }

  Future<_LessonMaterialManifest?> _readManifest({
    required String courseId,
    required String lessonId,
    bool refresh = false,
  }) async {
    final key = _cacheKey(courseId, lessonId);
    if (!refresh && _manifestCache.containsKey(key)) {
      return _manifestCache[key];
    }
    try {
      final directory = await _lessonDirectory(courseId, lessonId);
      final file = File(
        '${directory.path}${Platform.pathSeparator}manifest.json',
      );
      if (!await file.exists()) {
        _manifestCache[key] = null;
        return null;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> ||
          data['version'] != _manifestVersion) {
        _manifestCache[key] = null;
        return null;
      }
      final manifest = _LessonMaterialManifest.fromJson(data);
      _manifestCache[key] = manifest;
      return manifest;
    } on Object {
      _manifestCache[key] = null;
      return null;
    }
  }

  Future<bool> _allFilesExist({
    required String courseId,
    required String lessonId,
    required _LessonMaterialManifest manifest,
  }) async {
    final directory = await _lessonDirectory(courseId, lessonId);
    for (final fileName in manifest.files.values) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}files'
        '${Platform.pathSeparator}$fileName',
      );
      if (!await file.exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _replaceDirectory({
    required Directory active,
    required Directory staging,
  }) async {
    final backup = Directory('${active.path}.old');
    if (await backup.exists()) {
      await backup.delete(recursive: true);
    }
    final hadActive = await active.exists();
    if (hadActive) {
      await active.rename(backup.path);
    }
    try {
      await staging.rename(active.path);
      if (await backup.exists()) {
        await backup.delete(recursive: true);
      }
    } catch (_) {
      if (await active.exists()) {
        await active.delete(recursive: true);
      }
      if (await backup.exists()) {
        await backup.rename(active.path);
      }
      rethrow;
    }
  }

  Future<void> _cleanupInterruptedDirectories(Directory active) async {
    final backup = Directory('${active.path}.old');
    if (await backup.exists()) {
      if (await active.exists()) {
        await backup.delete(recursive: true);
      } else {
        await backup.rename(active.path);
      }
    }
    if (!await active.parent.exists()) {
      return;
    }
    final stagingPrefix = '${active.path}.staging-';
    await for (final entity in active.parent.list()) {
      if (entity is Directory &&
          entity.path.startsWith(stagingPrefix) &&
          await entity.exists()) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<Directory> _rootDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}lesson_material_cache',
    );
  }

  Future<Directory> _lessonDirectory(String courseId, String lessonId) async {
    final root = await _rootDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}${_safe(_userId)}'
      '${Platform.pathSeparator}${_safe(courseId)}'
      '${Platform.pathSeparator}${_safe(lessonId)}',
    );
  }

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'signed-out';

  String _cacheKey(String courseId, String lessonId) =>
      '$_userId\u0000$courseId\u0000$lessonId';

  bool _hasUsableIds(String courseId, String lessonId) =>
      FirebaseAuth.instance.currentUser != null &&
      courseId.trim().isNotEmpty &&
      lessonId.trim().isNotEmpty;

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  String _fileNameFor(String storagePath) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(storagePath)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    final name = storagePath.split('/').last;
    final dot = name.lastIndexOf('.');
    final extension = dot >= 0 ? name.substring(dot).toLowerCase() : '.bin';
    return '${hash.toRadixString(16)}$extension';
  }
}

class _LessonMaterialManifest {
  const _LessonMaterialManifest({
    required this.fingerprint,
    required this.files,
    required this.totalBytes,
  });

  final String fingerprint;
  final Map<String, String> files;
  final int totalBytes;

  factory _LessonMaterialManifest.fromJson(Map<String, dynamic> data) {
    final rawFiles = data['files'];
    if (data['fingerprint'] is! String || rawFiles is! Map) {
      throw const FormatException('Invalid lesson material manifest.');
    }
    return _LessonMaterialManifest(
      fingerprint: data['fingerprint'] as String,
      files: {
        for (final entry in rawFiles.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      },
      totalBytes: data['totalBytes'] is num
          ? (data['totalBytes'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': LessonMaterialCacheService._manifestVersion,
    'fingerprint': fingerprint,
    'files': files,
    'totalBytes': totalBytes,
  };
}
