import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/lesson_whiteboard_board_set.dart';
import 'lesson_material_cache_types.dart';

typedef LessonMaterialCacheDownloader =
    Future<void> Function(String storagePath, File destination);

class LessonMaterialCacheService {
  LessonMaterialCacheService({
    this.supportedOverride,
    this.userIdOverride,
    this.rootDirectoryOverride,
    this.downloader,
  });

  static const int _manifestVersion = 1;
  final bool? supportedOverride;
  final String? userIdOverride;
  final Directory? rootDirectoryOverride;
  final LessonMaterialCacheDownloader? downloader;
  final Map<String, _LessonMaterialManifest?> _manifestCache = {};

  bool get supported => supportedOverride ?? Platform.isAndroid;

  Future<LessonMaterialCacheStatus> status({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return const LessonMaterialCacheStatus.unsupported();
    }
    final requested = lessonMaterialStoragePaths(boardSet);
    if (requested.isEmpty) {
      return const LessonMaterialCacheStatus(
        supported: true,
        hasCurrentCache: false,
        hasStaleCache: false,
        totalBytes: 0,
      );
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
    var presentCount = 0;
    var presentBytes = 0;
    for (final storagePath in requested) {
      final file = await _fileForStoragePath(
        courseId: courseId,
        lessonId: lessonId,
        manifest: manifest,
        storagePath: storagePath,
      );
      if (file == null || !await file.exists()) {
        continue;
      }
      presentCount += 1;
      presentBytes += await file.length();
    }
    final leftoverFiles = manifest.files.isNotEmpty;
    return LessonMaterialCacheStatus(
      supported: true,
      hasCurrentCache: presentCount == requested.length,
      hasStaleCache:
          presentCount != requested.length &&
          (presentCount > 0 || leftoverFiles),
      totalBytes: presentCount == requested.length
          ? presentBytes
          : manifest.totalBytes,
    );
  }

  Future<String?> localPath({
    required String courseId,
    required String lessonId,
    required String storagePath,
  }) async {
    if (!supported ||
        !_hasUsableIds(courseId, lessonId) ||
        storagePath.trim().isEmpty) {
      return null;
    }
    final manifest = await _readManifest(
      courseId: courseId,
      lessonId: lessonId,
    );
    if (manifest == null) {
      return null;
    }
    final file = await _fileForStoragePath(
      courseId: courseId,
      lessonId: lessonId,
      manifest: manifest,
      storagePath: storagePath,
    );
    if (file == null || !await file.exists()) {
      return null;
    }
    return file.path;
  }

  Future<void> putFiles({
    required String courseId,
    required String lessonId,
    required Map<String, List<int>> files,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId) || files.isEmpty) {
      return;
    }
    final manifest =
        await _readManifest(
          courseId: courseId,
          lessonId: lessonId,
          refresh: true,
        ) ??
        const _LessonMaterialManifest(
          fingerprint: '',
          files: {},
          totalBytes: 0,
        );
    final nextFiles = Map<String, String>.from(manifest.files);
    final directory = await _filesDirectory(courseId, lessonId);
    await directory.create(recursive: true);
    for (final entry in files.entries) {
      final storagePath = entry.key.trim();
      if (storagePath.isEmpty || entry.value.isEmpty) {
        continue;
      }
      final fileName = _fileNameFor(storagePath);
      final destination = File(
        '${directory.path}${Platform.pathSeparator}$fileName',
      );
      await destination.writeAsBytes(
        Uint8List.fromList(entry.value),
        flush: true,
      );
      nextFiles[storagePath] = fileName;
    }
    await _writeManifest(
      courseId: courseId,
      lessonId: lessonId,
      files: nextFiles,
    );
  }

  Future<void> removeFiles({
    required String courseId,
    required String lessonId,
    required Iterable<String> storagePaths,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return;
    }
    final paths = {
      for (final path in storagePaths)
        if (path.trim().isNotEmpty) path.trim(),
    };
    if (paths.isEmpty) {
      return;
    }
    final manifest = await _readManifest(
      courseId: courseId,
      lessonId: lessonId,
      refresh: true,
    );
    if (manifest == null) {
      return;
    }
    final nextFiles = Map<String, String>.from(manifest.files);
    final directory = await _filesDirectory(courseId, lessonId);
    for (final storagePath in paths) {
      final fileName =
          nextFiles.remove(storagePath) ?? _fileNameFor(storagePath);
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (nextFiles.isEmpty) {
      await deleteLesson(courseId: courseId, lessonId: lessonId);
      return;
    }
    await _writeManifest(
      courseId: courseId,
      lessonId: lessonId,
      files: nextFiles,
    );
  }

  Future<LessonMaterialDownloadOutcome> downloadLesson({
    required String courseId,
    required String lessonId,
    required BoardSet boardSet,
    required void Function(LessonMaterialDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
    bool overwriteExisting = true,
    bool deleteUnlistedFiles = true,
    bool skipIfCurrent = false,
  }) async {
    if (!supported || !_hasUsableIds(courseId, lessonId)) {
      return LessonMaterialDownloadOutcome.nothingToDownload;
    }
    final storagePaths = lessonMaterialStoragePaths(boardSet);
    if (storagePaths.isEmpty) {
      if (deleteUnlistedFiles) {
        await deleteLesson(courseId: courseId, lessonId: lessonId);
      }
      return LessonMaterialDownloadOutcome.nothingToDownload;
    }
    if (skipIfCurrent) {
      final current = await status(
        courseId: courseId,
        lessonId: lessonId,
        boardSet: boardSet,
      );
      if (current.hasCurrentCache) {
        return LessonMaterialDownloadOutcome.skippedAlreadyCurrent;
      }
    }

    final manifest =
        await _readManifest(
          courseId: courseId,
          lessonId: lessonId,
          refresh: true,
        ) ??
        const _LessonMaterialManifest(
          fingerprint: '',
          files: {},
          totalBytes: 0,
        );
    final nextFiles = deleteUnlistedFiles
        ? <String, String>{}
        : Map<String, String>.from(manifest.files);
    final directory = await _filesDirectory(courseId, lessonId);
    await directory.create(recursive: true);

    try {
      for (final entry in storagePaths.indexed) {
        if (isCancelled()) {
          throw const LessonMaterialCacheCancelled();
        }
        final storagePath = entry.$2;
        final fileName = _fileNameFor(storagePath);
        final destination = File(
          '${directory.path}${Platform.pathSeparator}$fileName',
        );
        final canReuse =
            !overwriteExisting &&
            await destination.exists() &&
            await destination.length() > 0;
        if (canReuse) {
          nextFiles[storagePath] = fileName;
          onProgress(
            LessonMaterialDownloadProgress(
              downloadedBytes: (entry.$1 + 1) * 1000,
              totalBytes: storagePaths.length * 1000,
              completedFiles: entry.$1 + 1,
              totalFiles: storagePaths.length,
            ),
          );
          continue;
        }
        final staging = File('${destination.path}.part');
        if (await staging.exists()) {
          await staging.delete();
        }
        await _downloadToFile(
          storagePath: storagePath,
          destination: staging,
          isCancelled: isCancelled,
        );
        if (isCancelled()) {
          throw const LessonMaterialCacheCancelled();
        }
        if (await destination.exists()) {
          await destination.delete();
        }
        await staging.rename(destination.path);
        nextFiles[storagePath] = fileName;
        onProgress(
          LessonMaterialDownloadProgress(
            downloadedBytes: (entry.$1 + 1) * 1000,
            totalBytes: storagePaths.length * 1000,
            completedFiles: entry.$1 + 1,
            totalFiles: storagePaths.length,
          ),
        );
      }

      await _writeManifest(
        courseId: courseId,
        lessonId: lessonId,
        files: nextFiles,
      );
      if (deleteUnlistedFiles) {
        await _deleteUnlistedFiles(
          directory: directory,
          keepFileNames: nextFiles.values.toSet(),
        );
      }
      return LessonMaterialDownloadOutcome.downloaded;
    } finally {
      await _deletePartFiles(directory);
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

  Future<void> _downloadToFile({
    required String storagePath,
    required File destination,
    required bool Function() isCancelled,
  }) async {
    if (downloader != null) {
      await downloader!(storagePath, destination);
      return;
    }
    final task = FirebaseStorage.instance
        .ref(storagePath)
        .writeToFile(destination);
    late final StreamSubscription<TaskSnapshot> subscription;
    subscription = task.snapshotEvents.listen((_) {
      if (isCancelled()) {
        unawaited(task.cancel());
      }
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
  }

  Future<void> _writeManifest({
    required String courseId,
    required String lessonId,
    required Map<String, String> files,
  }) async {
    var totalBytes = 0;
    final directory = await _filesDirectory(courseId, lessonId);
    for (final fileName in files.values) {
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      if (await file.exists()) {
        totalBytes += await file.length();
      }
    }
    final keys = files.keys.toList()..sort();
    final manifest = _LessonMaterialManifest(
      fingerprint: keys.join('\n'),
      files: files,
      totalBytes: totalBytes,
    );
    final lessonDirectory = await _lessonDirectory(courseId, lessonId);
    await lessonDirectory.create(recursive: true);
    await File(
      '${lessonDirectory.path}${Platform.pathSeparator}manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
    _manifestCache[_cacheKey(courseId, lessonId)] = manifest;
  }

  Future<File?> _fileForStoragePath({
    required String courseId,
    required String lessonId,
    required _LessonMaterialManifest manifest,
    required String storagePath,
  }) async {
    final fileName = manifest.files[storagePath];
    if (fileName == null) {
      return null;
    }
    final directory = await _filesDirectory(courseId, lessonId);
    return File('${directory.path}${Platform.pathSeparator}$fileName');
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

  Future<void> _deleteUnlistedFiles({
    required Directory directory,
    required Set<String> keepFileNames,
  }) async {
    if (!await directory.exists()) {
      return;
    }
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path.split(Platform.pathSeparator).last
          : entity.uri.pathSegments.last;
      if (name.endsWith('.part') || keepFileNames.contains(name)) {
        continue;
      }
      await entity.delete();
    }
  }

  Future<void> _deletePartFiles(Directory directory) async {
    if (!await directory.exists()) {
      return;
    }
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path.endsWith('.part') &&
          await entity.exists()) {
        await entity.delete();
      }
    }
  }

  Future<Directory> _rootDirectory() async {
    if (rootDirectoryOverride != null) {
      return rootDirectoryOverride!;
    }
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

  Future<Directory> _filesDirectory(String courseId, String lessonId) async {
    final lesson = await _lessonDirectory(courseId, lessonId);
    return Directory('${lesson.path}${Platform.pathSeparator}files');
  }

  String get _userId =>
      userIdOverride ?? FirebaseAuth.instance.currentUser?.uid ?? 'signed-out';

  String _cacheKey(String courseId, String lessonId) =>
      '$_userId\u0000$courseId\u0000$lessonId';

  bool _hasUsableIds(String courseId, String lessonId) {
    final userId = userIdOverride ?? FirebaseAuth.instance.currentUser?.uid;
    return userId != null &&
        userId.isNotEmpty &&
        courseId.trim().isNotEmpty &&
        lessonId.trim().isNotEmpty;
  }

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
