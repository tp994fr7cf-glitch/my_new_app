import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_duration_parser.dart';
import '../models/lesson_media_config.dart';
import '../models/lesson_media_segment.dart';
import '../models/lesson_player_view_state.dart';
import '../models/lesson_whiteboard.dart';
import '../services/lesson_media_duration_service.dart';
import '../services/lesson_media_storage_service.dart';
import '../widgets/lesson_whiteboard_editor_panel.dart';
import 'teacher_quiz_manage_page.dart';

typedef LessonSaveOverride = Future<void> Function(List<CourseLesson> lessons);

class TeacherLessonManagePage extends StatefulWidget {
  const TeacherLessonManagePage({
    super.key,
    required this.course,
    this.onSaveOverride,
  });

  final Course course;
  final LessonSaveOverride? onSaveOverride;

  @override
  State<TeacherLessonManagePage> createState() =>
      _TeacherLessonManagePageState();
}

class _TeacherLessonManagePageState extends State<TeacherLessonManagePage> {
  static const _mediaStorageService = LessonMediaStorageService();
  static const _durationService = LessonMediaDurationService();
  static const _mediaConfig = LessonMediaConfig.current;

  late List<_LessonEditorState> _lessonEditors;
  late Course _activeCourse;
  bool _isSaving = false;
  bool _isLoadingLessons = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _activeCourse = widget.course;
    _lessonEditors = _activeCourse.lessons
        .map(_LessonEditorState.fromLesson)
        .toList();
    unawaited(_loadLatestLessons());
  }

  @override
  void dispose() {
    for (final editor in _lessonEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLatestLessons() async {
    final courseId = widget.course.id;
    if (courseId == null || widget.onSaveOverride != null) {
      return;
    }

    setState(() {
      _isLoadingLessons = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .get();
      if (!mounted || !snapshot.exists) {
        return;
      }

      final latestCourse = Course.fromFirestore(snapshot);
      setState(() {
        _activeCourse = latestCourse;
        for (final editor in _lessonEditors) {
          editor.dispose();
        }
        _lessonEditors = latestCourse.lessons
            .map(_LessonEditorState.fromLesson)
            .toList();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '保存済みレッスン情報の読み込みに失敗しました。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLessons = false;
        });
      }
    }
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '入力してください';
    }
    return null;
  }

  List<CourseLesson>? _buildLessons() {
    final lessons = <CourseLesson>[];

    for (final editor in _lessonEditors) {
      final title = editor.titleController.text.trim();
      if (title.isEmpty) {
        setState(() {
          _message = 'レッスンタイトルを入力してください。';
        });
        return null;
      }

      final durationLabel = editor.durationController.text.trim().isEmpty
          ? '1分30秒'
          : editor.durationController.text.trim();
      final segments = editor.buildSegments(fallbackDurationLabel: durationLabel);
      final publishedLayers = resolveWhiteboardLayersForLessonPublish(
        publishedLayers: editor.publishedWhiteboardLayers,
        draftLayers: editor.draftWhiteboardLayers,
        workingLayers: editor.workingWhiteboardLayers,
      );

      lessons.add(
        CourseLesson(
          title: title,
          duration: durationLabel,
          mediaSegments: segments,
          isPreview: editor.isPreview,
          whiteboardLayers: publishedLayers,
          whiteboardDraftLayers: const [],
        ),
      );
    }

    return lessons;
  }

  Future<void> _saveLessons() async {
    final lessons = _buildLessons();
    if (lessons == null) {
      return;
    }

    final courseId = widget.course.id;
    if (courseId == null && widget.onSaveOverride == null) {
      setState(() {
        _message = '講座IDがないため保存できません。';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final saveOverride = widget.onSaveOverride;
      if (saveOverride != null) {
        await saveOverride(lessons);
      } else {
        await FirebaseFirestore.instance
            .collection('courses')
            .doc(courseId)
            .update({
              'lessons': lessons.map((lesson) => lesson.toMap()).toList(),
              'lessonCount': lessons.length,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) {
        setState(() {
          for (var index = 0; index < _lessonEditors.length; index++) {
            if (index >= lessons.length) {
              continue;
            }
            final editor = _lessonEditors[index];
            final savedLesson = lessons[index];
            editor.publishedWhiteboardLayers = savedLesson.whiteboardLayers;
            editor.draftWhiteboardLayers = const [];
            editor.workingWhiteboardLayers = savedLesson.publishedWhiteboardBundle;
          }
          _message = 'レッスン情報を保存しました。';
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message ?? 'レッスン情報の保存に失敗しました。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'エラーが発生しました: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _uploadSegmentMedia({
    required int lessonNumber,
    required _LessonEditorState editor,
    required _MediaSegmentEditorState segment,
  }) async {
    final courseId = widget.course.id;
    if (courseId == null) {
      setState(() {
        _message = '講座IDがないためアップロードできません。';
      });
      return;
    }

    final shouldPick = await _showUploadGuideDialog(mediaType: segment.mediaType);
    if (!shouldPick || !mounted) {
      return;
    }

    setState(() {
      _message = null;
    });

    PlatformFile? pickedFile;
    try {
      pickedFile = await _mediaStorageService.pickLessonMediaFile(
        mediaType: segment.mediaType,
      );
    } on LessonMediaStorageException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
      return;
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'ファイル選択に失敗しました: $error';
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    if (pickedFile == null) {
      setState(() {
        _message = 'ファイル選択をキャンセルしました。';
      });
      return;
    }

    setState(() {
      segment.isUploading = true;
      segment.uploadProgress = 0;
      _message = null;
    });

    try {
      final result = await _mediaStorageService.uploadLessonMediaFile(
        courseId: courseId,
        lessonNumber: lessonNumber,
        segmentId: segment.id,
        mediaType: segment.mediaType,
        pickedFile: pickedFile,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            segment.uploadProgress = progress;
          });
        },
      );
      if (!mounted) {
        return;
      }

      final detectedDurationSec = await _durationService.detectDurationSec(
        pickedFile,
      );

      segment.urlController.text = result.downloadUrl;
      if (detectedDurationSec != null && detectedDurationSec > 0) {
        segment.durationSec = detectedDurationSec;
      }
      setState(() {
        segment.isUploading = false;
        segment.uploadProgress = null;
        _message =
            'レッスン$lessonNumber のパート${segment.displayOrder}に'
            '${_mediaStorageService.mediaTypeLabel(segment.mediaType)}をアップロードしました。'
            '${detectedDurationSec != null ? '（再生時間: ${detectedDurationSec}秒）' : ''}'
            '「レッスン情報を保存」を押して反映してください。';
      });
    } on LessonMediaStorageException catch (error) {
      if (mounted) {
        setState(() {
          segment.isUploading = false;
          segment.uploadProgress = null;
          _message = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          segment.isUploading = false;
          segment.uploadProgress = null;
          _message = 'アップロードに失敗しました: $error';
        });
      }
    }
  }

  Future<bool> _showUploadGuideDialog({required String mediaType}) async {
    final mediaLabel = _mediaStorageService.mediaTypeLabel(mediaType);
    final allowedExtensions = _mediaStorageService.allowedExtensionsForMediaType(
      mediaType,
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('$mediaLabelファイルを選びます'),
          content: SingleChildScrollView(
            child: Text(
              '端末内の$mediaLabelファイルを選んでアップロードします。\n\n'
              '【エミュレータの場合】\n'
              '最初は「まだ一つも項目がありません」と出ることがあります。\n'
              'その場合は、先に PC から音声ファイルを Download フォルダへ入れてください。\n\n'
              '1. 画面の ≡（メニュー）または「ダウンロード」を開く\n'
              '2. test.mp3 などを選ぶ\n'
              '3. 戻るときは端末画面下の ◁（戻る）ボタン\n\n'
              '【対応形式】\n'
              '${allowedExtensions.join(' / ')}（50MBまで）',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ファイルを選ぶ'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _saveWhiteboardDraft({
    required int lessonIndex,
    required _LessonEditorState editor,
    required LessonWhiteboard whiteboard,
  }) async {
    final courseId = widget.course.id;
    if (courseId == null) {
      throw StateError('講座IDがないため一時保存できません。');
    }

    await saveLessonWhiteboardDraft(
      courseId: courseId,
      lessonIndex: lessonIndex,
      whiteboard: whiteboard,
    );

    if (mounted) {
      setState(() {
        final draftLayers = LessonWhiteboardLayerBundle.fromLegacyWhiteboard(
          whiteboard.isEmpty ? null : whiteboard,
        ).layers;
        editor.draftWhiteboardLayers = draftLayers;
        editor.workingWhiteboardLayers =
            LessonWhiteboardLayerBundle(layers: draftLayers);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseId = widget.course.id;
    final canUploadMedia = courseId != null && courseId.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('レッスン管理')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.course.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1レッスンに複数の音声・動画パートを追加できます。'
              'アップロード後は「レッスン情報を保存」を押してください。',
            ),
            if (!canUploadMedia) ...[
              const SizedBox(height: 8),
              Text(
                '講座IDがないため、この画面ではアップロードできません。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (_isLoadingLessons) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            for (final entry in _lessonEditors.indexed) ...[
              _LessonEditorCard(
                index: entry.$1 + 1,
                lessonIndex: entry.$1,
                course: _activeCourse,
                editor: entry.$2,
                canUploadMedia: canUploadMedia,
                mediaConfig: _mediaConfig,
                requiredText: _requiredText,
                onChanged: () => setState(() {}),
                onUploadSegment: (segment) => _uploadSegmentMedia(
                  lessonNumber: entry.$1 + 1,
                  editor: entry.$2,
                  segment: segment,
                ),
                onDraftSaved: (whiteboard) => _saveWhiteboardDraft(
                  lessonIndex: entry.$1,
                  editor: entry.$2,
                  whiteboard: whiteboard,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_message != null) ...[
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isSaving) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveLessons,
              icon: const Icon(Icons.save),
              label: const Text('レッスン情報を保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaSegmentEditorState {
  _MediaSegmentEditorState({
    required this.id,
    required this.order,
    required this.titleController,
    required this.urlController,
    required this.mediaType,
    this.durationSec = 0,
    this.isUploading = false,
    this.uploadProgress,
  });

  factory _MediaSegmentEditorState.fromSegment(LessonMediaSegment segment) {
    return _MediaSegmentEditorState(
      id: segment.id,
      order: segment.order,
      titleController: TextEditingController(text: segment.title),
      urlController: TextEditingController(text: segment.url),
      mediaType: segment.isAudio ? 'audio' : 'video',
      durationSec: segment.durationSec,
    );
  }

  final String id;
  int order;
  final TextEditingController titleController;
  final TextEditingController urlController;
  String mediaType;
  int durationSec;
  bool isUploading;
  double? uploadProgress;

  int get displayOrder => order + 1;

  bool get hasUrl => urlController.text.trim().isNotEmpty;

  LessonMediaSegment toSegment({required int fallbackDurationSec}) {
    final duration = durationSec > 0 ? durationSec : fallbackDurationSec;
    return LessonMediaSegment(
      id: id,
      order: order,
      title: titleController.text.trim(),
      mediaType: mediaType == 'audio' ? 'audio' : 'video',
      url: urlController.text.trim(),
      durationSec: hasUrl ? duration : 0,
    );
  }

  void dispose() {
    titleController.dispose();
    urlController.dispose();
  }
}

class _LessonEditorState {
  _LessonEditorState({
    required this.titleController,
    required this.durationController,
    required this.segments,
    required this.isPreview,
    this.publishedWhiteboardLayers = const [],
    this.draftWhiteboardLayers = const [],
    LessonWhiteboardLayerBundle? workingWhiteboardLayers,
  }) : workingWhiteboardLayers =
           workingWhiteboardLayers ??
           mergeWhiteboardDraftLayers(
             published: LessonWhiteboardLayerBundle(
               layers: publishedWhiteboardLayers,
             ),
             draft: LessonWhiteboardLayerBundle(layers: draftWhiteboardLayers),
           );

  factory _LessonEditorState.fromLesson(CourseLesson lesson) {
    final segments = lesson.mediaSegments.isEmpty
        ? <_MediaSegmentEditorState>[]
        : lesson.mediaSegments
              .map(_MediaSegmentEditorState.fromSegment)
              .toList();

    return _LessonEditorState(
      titleController: TextEditingController(text: lesson.title),
      durationController: TextEditingController(text: lesson.duration),
      segments: segments,
      isPreview: lesson.isPreview,
      publishedWhiteboardLayers: lesson.whiteboardLayers,
      draftWhiteboardLayers: lesson.whiteboardDraftLayers,
      workingWhiteboardLayers: mergeWhiteboardDraftLayers(
        published: lesson.publishedWhiteboardBundle,
        draft: lesson.draftWhiteboardBundle,
      ),
    );
  }

  final TextEditingController titleController;
  final TextEditingController durationController;
  final List<_MediaSegmentEditorState> segments;
  bool isPreview;
  List<LessonWhiteboardLayer> publishedWhiteboardLayers;
  List<LessonWhiteboardLayer> draftWhiteboardLayers;
  LessonWhiteboardLayerBundle workingWhiteboardLayers;

  bool get isAnySegmentUploading => segments.any((segment) => segment.isUploading);

  bool get hasPlayableMedia => segments.any((segment) => segment.hasUrl);

  bool get hasAudioSegment =>
      segments.any((segment) => segment.mediaType == 'audio' && segment.hasUrl);

  List<LessonMediaSegment> buildSegments({required String fallbackDurationLabel}) {
    final fallbackDurationSec = parseLessonDurationLabel(fallbackDurationLabel) ?? 0;
    return LessonMediaSegment.normalizeOrders(
      segments
          .map(
            (segment) => segment.toSegment(fallbackDurationSec: fallbackDurationSec),
          )
          .where((segment) => segment.hasUrl)
          .toList(),
    );
  }

  _MediaSegmentEditorState addSegment({String mediaType = 'audio'}) {
    final segment = _MediaSegmentEditorState(
      id: LessonMediaSegment.generateId(),
      order: segments.length,
      titleController: TextEditingController(),
      urlController: TextEditingController(),
      mediaType: mediaType,
    );
    segments.add(segment);
    return segment;
  }

  void moveSegmentUp(int index) {
    if (index <= 0 || index >= segments.length) {
      return;
    }
    final item = segments.removeAt(index);
    segments.insert(index - 1, item);
    _reindexSegments();
  }

  void moveSegmentDown(int index) {
    if (index < 0 || index >= segments.length - 1) {
      return;
    }
    final item = segments.removeAt(index);
    segments.insert(index + 1, item);
    _reindexSegments();
  }

  void removeSegmentAt(int index) {
    if (index < 0 || index >= segments.length) {
      return;
    }
    segments.removeAt(index).dispose();
    _reindexSegments();
  }

  void _reindexSegments() {
    for (var index = 0; index < segments.length; index++) {
      segments[index].order = index;
    }
  }

  void dispose() {
    titleController.dispose();
    durationController.dispose();
    for (final segment in segments) {
      segment.dispose();
    }
  }
}

class _LessonEditorCard extends StatelessWidget {
  const _LessonEditorCard({
    required this.index,
    required this.lessonIndex,
    required this.course,
    required this.editor,
    required this.canUploadMedia,
    required this.mediaConfig,
    required this.requiredText,
    required this.onChanged,
    required this.onUploadSegment,
    required this.onDraftSaved,
  });

  final int index;
  final int lessonIndex;
  final Course course;
  final _LessonEditorState editor;
  final bool canUploadMedia;
  final LessonMediaConfig mediaConfig;
  final String? Function(String? value) requiredText;
  final VoidCallback onChanged;
  final ValueChanged<_MediaSegmentEditorState> onUploadSegment;
  final WhiteboardDraftSaveCallback onDraftSaved;

  Future<void> _showAddSegmentDialog(BuildContext context) async {
    final mediaType = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('パートを追加'),
          content: const Text('追加するファイルの種類を選んでください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('audio'),
              child: const Text('音声'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('video'),
              child: const Text('動画'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
    if (mediaType == null) {
      return;
    }
    editor.addSegment(mediaType: mediaType);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    const mediaStorageService = LessonMediaStorageService();
    final courseId = course.id ?? '';
    final durationLabel = editor.durationController.text.trim().isEmpty
        ? '1分30秒'
        : editor.durationController.text.trim();
    final builtSegments = editor.buildSegments(fallbackDurationLabel: durationLabel);
    final canAddSegment = mediaConfig.canAddSegment(
      currentSegmentCount: editor.segments.length,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'レッスン$index',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.titleController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'レッスンタイトル',
              ),
              validator: requiredText,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: editor.durationController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '時間（目安）',
                hintText: '例: 1分30秒',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'メディアパート',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (editor.segments.isEmpty)
              const Text('パートはまだありません。必要なときだけ追加できます。'),
            for (final entry in editor.segments.indexed) ...[
              _SegmentEditorTile(
                segment: entry.$2,
                segmentIndex: entry.$1,
                segmentCount: editor.segments.length,
                canUploadMedia: canUploadMedia && !editor.isAnySegmentUploading,
                mediaStorageService: mediaStorageService,
                onChanged: onChanged,
                onUpload: () => onUploadSegment(entry.$2),
                onMoveUp: entry.$1 > 0
                    ? () {
                        editor.moveSegmentUp(entry.$1);
                        onChanged();
                      }
                    : null,
                onMoveDown: entry.$1 < editor.segments.length - 1
                    ? () {
                        editor.moveSegmentDown(entry.$1);
                        onChanged();
                      }
                    : null,
                onRemove: () {
                  editor.removeSegmentAt(entry.$1);
                  onChanged();
                },
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !canAddSegment || editor.isAnySegmentUploading
                      ? null
                      : () => unawaited(_showAddSegmentDialog(context)),
                  icon: const Icon(Icons.add),
                  label: const Text('パートを追加'),
                ),
                if (builtSegments.isNotEmpty)
                  Text('合計 ${builtSegments.fold<int>(0, (sum, s) => sum + s.durationSec)} 秒'),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('無料プレビュー'),
              value: editor.isPreview,
              onChanged: editor.isAnySegmentUploading
                  ? null
                  : (value) {
                      editor.isPreview = value;
                      onChanged();
                    },
            ),
            OutlinedButton.icon(
              onPressed: editor.isAnySegmentUploading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeacherQuizManagePage(
                            course: course,
                            lessonNumber: index,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.quiz),
              label: const Text('クイズを管理'),
            ),
            if (editor.hasAudioSegment && editor.hasPlayableMedia && courseId.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              LessonWhiteboardEditorPanel(
                key: ValueKey(
                  '${courseId}_${index}_${builtSegments.map((s) => s.id).join('_')}',
                ),
                courseId: courseId,
                lessonNumber: index,
                mediaSegments: builtSegments,
                durationLabel: durationLabel,
                publishedWhiteboard: editor.publishedWhiteboardLayers.toLegacyWhiteboard(),
                draftWhiteboard: editor.draftWhiteboardLayers.toLegacyWhiteboard(),
                onDraftSaved: onDraftSaved,
                onWhiteboardChanged: (whiteboard) {
                  editor.workingWhiteboardLayers =
                      LessonWhiteboardLayerBundle.fromLegacyWhiteboard(whiteboard);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentEditorTile extends StatelessWidget {
  const _SegmentEditorTile({
    required this.segment,
    required this.segmentIndex,
    required this.segmentCount,
    required this.canUploadMedia,
    required this.mediaStorageService,
    required this.onChanged,
    required this.onUpload,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final _MediaSegmentEditorState segment;
  final int segmentIndex;
  final int segmentCount;
  final bool canUploadMedia;
  final LessonMediaStorageService mediaStorageService;
  final VoidCallback onChanged;
  final VoidCallback onUpload;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mediaLabel = mediaStorageService.mediaTypeLabel(segment.mediaType);
    final allowedExtensions = mediaStorageService.allowedExtensionsForMediaType(
      segment.mediaType,
    );

    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'パート${segment.displayOrder}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: segment.titleController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'パートタイトル（任意）',
                hintText: 'あとから変更できます',
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: segment.mediaType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '種類',
              ),
              items: const [
                DropdownMenuItem(value: 'audio', child: Text('音声')),
                DropdownMenuItem(value: 'video', child: Text('動画')),
              ],
              onChanged: segment.isUploading
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      segment.mediaType = value;
                      onChanged();
                    },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !canUploadMedia || segment.isUploading ? null : onUpload,
              icon: Icon(
                segment.mediaType == 'audio'
                    ? Icons.upload_file
                    : Icons.video_file_outlined,
              ),
              label: Text('$mediaLabelをアップロード'),
            ),
            const SizedBox(height: 4),
            Text(
              '対応形式: ${allowedExtensions.join(' / ')}（50MBまで）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (segment.isUploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: segment.uploadProgress?.clamp(0, 1),
              ),
            ],
            if (segment.hasUrl) ...[
              const SizedBox(height: 8),
              Text(
                'URL: ${segment.urlController.text}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (segment.durationSec > 0)
                Text('長さ: ${segment.durationSec}秒'),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: '上へ',
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '下へ',
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: '削除',
                  onPressed: segment.isUploading ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on List<LessonWhiteboardLayer> {
  LessonWhiteboard? toLegacyWhiteboard() {
    return LessonWhiteboardLayerBundle(layers: this).toLegacyWhiteboard();
  }
}
