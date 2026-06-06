import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/public_user_profile.dart';
import '../services/lesson_interaction_service.dart';
import 'lesson_questions_page.dart';
import 'public_note_edit_history_sheet.dart';
import 'public_user_profile_page.dart';
import 'shared/lesson_note_preview_body.dart';

class LessonNotesPage extends StatelessWidget {
  const LessonNotesPage({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.notesStream,
    this.publicNotesStream,
    this.foldersStream,
    this.initialFocusNoteId,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonNote>>? notesStream;
  final Stream<List<LessonNote>>? publicNotesStream;
  final Stream<List<LessonNoteFolder>>? foldersStream;
  final String? initialFocusNoteId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レッスンメモ')),
      body: LessonNotesPanel(
        course: course,
        lesson: lesson,
        lessonNumber: lessonNumber,
        notesStream: notesStream,
        publicNotesStream: publicNotesStream,
        foldersStream: foldersStream,
        initialFocusNoteId: initialFocusNoteId,
      ),
    );
  }
}

class LessonNotesPanel extends StatefulWidget {
  const LessonNotesPanel({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.notesStream,
    this.publicNotesStream,
    this.foldersStream,
    this.isEmbedded = false,
    this.isTeacherPreview = false,
    this.initialFocusNoteId,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonNote>>? notesStream;
  final Stream<List<LessonNote>>? publicNotesStream;
  final Stream<List<LessonNoteFolder>>? foldersStream;
  final bool isEmbedded;
  final bool isTeacherPreview;
  final String? initialFocusNoteId;

  @override
  State<LessonNotesPanel> createState() => _LessonNotesPanelState();
}

class _LessonNotesPanelState extends State<LessonNotesPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _message;
  LessonNote? _editingNote;
  LessonNote? _previewingOwnNote;
  List<LessonNoteFolder> _editingFolders = const [];
  List<LessonNoteFolder> _previewFolders = const [];
  bool _isEditingNote = false;
  LessonNotePublicSort _publicSort = LessonNotePublicSort.newest;
  final LessonInteractionService _lessonInteractionService =
      const LessonInteractionService();

  String get _courseId => widget.course.storageId;

  String get _interactionSettingId =>
      _lessonInteractionService.settingDocumentId(
        courseId: _courseId,
        lessonNumber: widget.lessonNumber,
      );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<LessonNoteFolder>> _foldersStream() {
    final provided = widget.foldersStream;
    if (provided != null) {
      return provided;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonNoteFolders')
        .snapshots()
        .map((snapshot) {
          final folders =
              snapshot.docs
                  .map(LessonNoteFolder.fromFirestore)
                  .where((folder) => !folder.isDeleted)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
          return folders;
        });
  }

  Stream<List<LessonNote>> _notesStream() {
    final provided = widget.notesStream;
    if (provided != null) {
      return provided;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .snapshots()
        .map((snapshot) {
          return sortLessonNotesByUpdatedAt(
            snapshot.docs
                .map(LessonNote.fromFirestore)
                .where((note) => !note.isDeleted)
                .toList(),
          );
        });
  }

  Stream<List<LessonNote>> _publicNotesStream() {
    final provided = widget.publicNotesStream;
    if (provided != null) {
      return provided;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .where('interactionSettingId', isEqualTo: _interactionSettingId)
        .where('studentVisibility', isEqualTo: lessonNoteVisibilityPublic)
        .where('moderationStatus', isEqualTo: lessonNoteModerationVisible)
        .where('isDeleted', isEqualTo: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          if (snapshot.metadata.isFromCache) {
            return const <LessonNote>[];
          }
          return sortPublicLessonNotes(
            snapshot.docs
                .map(LessonNote.fromFirestore)
                .where((note) => note.isPubliclyVisible)
                .toList(),
            _publicSort,
          );
        });
  }

  Stream<List<LessonNote>> _teacherPreviewPublicNotesStream() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }

    return FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .where('interactionSettingId', isEqualTo: _interactionSettingId)
        .where('isDeleted', isEqualTo: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          if (snapshot.metadata.isFromCache) {
            return const <LessonNote>[];
          }
          return sortPublicLessonNotes(
            snapshot.docs.map(LessonNote.fromFirestore).toList(),
            _publicSort,
          );
        });
  }

  Stream<bool> _notePublicPlatformEnabledStream() {
    return _lessonInteractionService.publicFeatureEnabledStream(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonNotesPublicEnabledField,
    );
  }

  Future<bool> _isNotePublicPlatformEnabled() async {
    return _lessonInteractionService.isPublicFeatureEnabled(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonNotesPublicEnabledField,
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _message = message;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setPublicNoteModeration(LessonNote note) async {
    await _lessonInteractionService.setPublicModeration(
      collectionPath: 'publicLessonNotes',
      documentId: note.id,
      moderationStatus: note.isTeacherHidden
          ? lessonNoteModerationVisible
          : lessonNoteModerationHiddenByTeacher,
    );
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CreateFolderDialog(),
    );

    if (name == null || name.isEmpty) {
      return;
    }

    if (Firebase.apps.isEmpty) {
      setState(() {
        _message = 'フォルダ保存にはログインとFirebase設定が必要です。';
      });
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _message = 'フォルダ保存にはログインが必要です。';
      });
      return;
    }

    final now = FieldValue.serverTimestamp();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lessonNoteFolders')
        .add({'name': name, 'createdAt': now, 'updatedAt': now});
  }

  Future<void> _openEditor({
    LessonNote? note,
    required List<LessonNoteFolder> folders,
  }) async {
    if (widget.isEmbedded) {
      setState(() {
        _editingNote = note;
        _editingFolders = folders;
        _isEditingNote = true;
      });
      return;
    }
    await _pushEditorPage(
      context,
      note: note,
      folders: folders,
    );
  }

  Future<void> _pushEditorPage(
    BuildContext navigationContext, {
    LessonNote? note,
    required List<LessonNoteFolder> folders,
  }) async {
    await Navigator.of(navigationContext).push(
      MaterialPageRoute(
        builder: (_) => _LessonNoteEditorPage(
          note: note,
          folders: folders,
          course: widget.course,
          lesson: widget.lesson,
          lessonNumber: widget.lessonNumber,
          onSave: _saveNote,
        ),
      ),
    );
  }

  Future<void> _openOwnNotePreview({
    required LessonNote note,
    required List<LessonNoteFolder> folders,
  }) async {
    if (widget.isEmbedded) {
      setState(() {
        _previewingOwnNote = note;
        _previewFolders = folders;
        _isEditingNote = false;
      });
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PublicLessonNoteDetailPage(
          note: note,
          course: widget.course,
          lesson: widget.lesson,
          lessonNumber: widget.lessonNumber,
          canCreateQuestion: !widget.isTeacherPreview && note.isPubliclyVisible,
          onEdit: (pageContext) =>
              _pushEditorPage(pageContext, note: note, folders: folders),
        ),
      ),
    );
  }

  Future<void> _openPublicNotePreview(LessonNote note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PublicLessonNoteDetailPage(
          note: note,
          course: widget.course,
          lesson: widget.lesson,
          lessonNumber: widget.lessonNumber,
          canCreateQuestion: !widget.isTeacherPreview,
          onEdit: _canCurrentUserEditNote(note)
              ? (pageContext) async {
                  final folders = await _foldersStream().first;
                  if (!mounted || !pageContext.mounted) {
                    return;
                  }
                  await _pushEditorPage(
                    pageContext,
                    note: note,
                    folders: folders,
                  );
                }
              : null,
        ),
      ),
    );
  }

  bool _canCurrentUserEditNote(LessonNote note) {
    if (widget.isTeacherPreview || Firebase.apps.isEmpty) {
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid.isNotEmpty && uid == note.authorId;
  }

  Future<bool> _saveNote(_LessonNoteDraft draft) async {
    if (Firebase.apps.isEmpty) {
      _showMessage('メモ保存にはログインとFirebase設定が必要です。');
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('メモ保存にはログインが必要です。');
      return false;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final noteRef = draft.noteId == null
          ? userRef.collection('lessonNotes').doc()
          : userRef.collection('lessonNotes').doc(draft.noteId);
      final noteId = noteRef.id;
      final nowClientUtc = DateTime.now().toUtc();
      final visibility = draft.visibility == LessonNoteVisibility.public
          ? lessonNoteVisibilityPublic
          : draft.visibility == LessonNoteVisibility.teacherOnly
          ? lessonNoteVisibilityTeacherOnly
          : lessonNoteVisibilityPrivate;
      final now = FieldValue.serverTimestamp();
      final authorName = user.displayName ?? user.email ?? '学習者';
      final existingNoteSnapshot = await noteRef.get();
      final existingData = existingNoteSnapshot.data();
      final previousTitle = existingData?['title'] as String? ?? '';
      final previousBody = existingData?['body'] as String? ?? '';
      final contentChanged =
          existingData != null &&
          (previousTitle != draft.title || previousBody != draft.body);
      final existingAllowsQuestionCitation =
          existingData?['allowsQuestionCitation'] == true;
      final existingHasPublicMirror =
          existingData?['hasPublicMirror'] == true ||
          existingData?['visibility'] == lessonNoteVisibilityPublic ||
          existingData?['visibility'] == lessonNoteVisibilityTeacherOnly;
      final canPublish = canPublishLessonNote(
        hasAudioAttachment: draft.attachmentTypes.contains(
          lessonNoteAttachmentAudio,
        ),
        isCopied: draft.isCopied,
        canPublish: draft.canPublish,
      );
      final platformEnabled = await _isNotePublicPlatformEnabled();
      final isPublicLocked = draft.wasPublic;
      final savedVisibility = isPublicLocked
          ? lessonNoteVisibilityPublic
          : switch (visibility) {
              lessonNoteVisibilityPublic => canPublish && platformEnabled
                  ? lessonNoteVisibilityPublic
                  : lessonNoteVisibilityPrivate,
              lessonNoteVisibilityTeacherOnly => canPublish
                  ? lessonNoteVisibilityTeacherOnly
                  : lessonNoteVisibilityPrivate,
              _ => lessonNoteVisibilityPrivate,
            };
      final publicRef = firestore.collection('publicLessonNotes').doc(noteId);
      // New public notes do not have a mirror yet, so avoid pre-reading
      // /publicLessonNotes/{noteId} before create. This prevents false
      // permission-denied failures on first publish.
      final shouldReadPublicMirror = existingHasPublicMirror;
      final publicSnapshotResult = await _publicNoteSnapshotForSave(
        publicRef,
        shouldRead: shouldReadPublicMirror,
      );
      if (publicSnapshotResult.permissionDenied) {
        _showMessage('公開メモの確認権限がないため保存できませんでした。');
        return false;
      }
      final publicSnapshot = publicSnapshotResult.snapshot;
      final publicData = publicSnapshot?.data();
      final hasPublicMirror = publicSnapshot?.exists ?? false;
      final nextHasPublicMirror =
          savedVisibility != lessonNoteVisibilityPrivate || hasPublicMirror;
      final publicModerationStatus =
          publicData?['moderationStatus'] as String? ??
          lessonNoteModerationVisible;
      final hasJustEnabledCitation =
          draft.allowsQuestionCitation && !existingAllowsQuestionCitation;
      final citationEnabledAt = draft.allowsQuestionCitation
          ? (hasJustEnabledCitation
                ? Timestamp.fromDate(nowClientUtc)
                : existingData?['citationEnabledAt'] as Timestamp? ??
                      Timestamp.fromDate(nowClientUtc))
          : null;
      final citationFreeEditUntil = draft.allowsQuestionCitation
          ? (hasJustEnabledCitation
                ? Timestamp.fromDate(
                    nowClientUtc.add(lessonNoteCitationEditFreeWindow),
                  )
                : resolveLessonNoteCitationFreeEditUntil(
                    allowsQuestionCitation: true,
                    citationEnabledAt:
                        existingData?['citationEnabledAt'] as Timestamp?,
                    citationFreeEditUntil:
                        existingData?['citationFreeEditUntil'] as Timestamp?,
                    publicPublishedAt:
                        (existingData?['publicPublishedAt'] as Timestamp?) ??
                        (publicData?['publicPublishedAt'] as Timestamp?),
                    createdAt: existingData?['createdAt'] as Timestamp?,
                  ) ??
                      Timestamp.fromDate(
                        nowClientUtc.add(lessonNoteCitationEditFreeWindow),
                      ))
          : null;
      final citationProtectedBeforeEdit =
          existingAllowsQuestionCitation && existingHasPublicMirror;
      final shouldRecordCitationEditHistory =
          citationProtectedBeforeEdit && contentChanged;
      var countsTowardWeeklyLimit = false;
      if (shouldRecordCitationEditHistory &&
          !isWithinLessonNoteCitationFreeEditWindow(
            nowUtc: nowClientUtc,
            citationFreeEditUntil: citationFreeEditUntil,
          )) {
        final recentCountSnapshot = await publicRef
            .collection(publicLessonNoteEditHistoryCollection)
            .where(
              'editedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                nowClientUtc.subtract(lessonNoteCitationCompareRetentionWindow),
              ),
            )
            .orderBy('editedAt', descending: true)
            .get();
        final lockUntil = lessonNoteEditLockUntil(
          countableEditTimes: recentCountSnapshot.docs
              .where((doc) => doc.data()['countsTowardWeeklyLimit'] == true)
              .map((doc) => doc.data()['editedAt'] as Timestamp?)
              .whereType<Timestamp>(),
          now: nowClientUtc,
        );
        if (lockUntil != null) {
          _showMessage(
            '過去7日間の編集回数が上限（3回）に達しました。${_formatEditUnlockTime(lockUntil)} 以降に再編集できます。',
          );
          return false;
        }
        countsTowardWeeklyLimit = true;
      }
      final existingCitationEditCount =
          (existingData?['citationEditCount'] as num?)?.toInt() ?? 0;
      final nextCitationEditCount = shouldRecordCitationEditHistory
          ? existingCitationEditCount + 1
          : existingCitationEditCount;
      final staleComparisonSnapshots = shouldRecordCitationEditHistory
          ? await publicRef
                .collection(publicLessonNoteEditHistoryCollection)
                .where(
                  'compareVisibleUntil',
                  isLessThan: Timestamp.fromDate(nowClientUtc),
                )
                .limit(100)
                .get()
          : null;
      final data = {
        'userId': user.uid,
        'authorId': user.uid,
        'authorName': authorName,
        'title': draft.title,
        'body': draft.body,
        'folderId': draft.folderId,
        'folderName': draft.folderName,
        'courseId': _courseId,
        'courseTitle': widget.course.title,
        'lessonNumber': widget.lessonNumber,
        'lessonTitle': widget.lesson.title,
        'visibility': savedVisibility,
        'tags': draft.tags,
        'attachmentTypes': draft.attachmentTypes,
        'hasAudioAttachment': draft.attachmentTypes.contains(
          lessonNoteAttachmentAudio,
        ),
        'sourceNoteId': draft.sourceNoteId,
        'sourceAuthorId': draft.sourceAuthorId,
        'isCopied': draft.isCopied,
        'canPublish': draft.canPublish,
        'allowsQuestionCitation': draft.allowsQuestionCitation,
        if (draft.allowsQuestionCitation) 'citationEnabledAt': citationEnabledAt,
        if (draft.allowsQuestionCitation)
          'citationFreeEditUntil': citationFreeEditUntil,
        if (draft.allowsQuestionCitation) 'citationEditCount': nextCitationEditCount,
        if (shouldRecordCitationEditHistory) 'lastCitationEditedAt': now,
        if (!shouldRecordCitationEditHistory &&
            existingData?['lastCitationEditedAt'] != null)
          'lastCitationEditedAt': existingData?['lastCitationEditedAt'],
        'hasPublicMirror': nextHasPublicMirror,
        'isDeleted': false,
        'moderationStatus': lessonNoteModerationVisible,
        'updatedAt': now,
        if (draft.noteId == null) 'createdAt': now,
      };

      final batch = firestore.batch()
        ..set(noteRef, data, SetOptions(merge: true));
      if (savedVisibility != lessonNoteVisibilityPrivate) {
        batch.set(publicRef, {
          ...data,
          'noteId': noteId,
          'interactionSettingId': _lessonInteractionService.settingDocumentId(
            courseId: _courseId,
            lessonNumber: widget.lessonNumber,
          ),
          'visibility': lessonNoteVisibilityPublic,
          'studentVisibility': savedVisibility,
          'moderationStatus': publicModerationStatus,
          'publicPublishedAt': publicData?['publicPublishedAt'] ?? now,
          if (draft.allowsQuestionCitation) 'citationEnabledAt': citationEnabledAt,
          if (draft.allowsQuestionCitation)
            'citationFreeEditUntil': citationFreeEditUntil,
          if (draft.allowsQuestionCitation)
            'citationEditCount': nextCitationEditCount,
          if (shouldRecordCitationEditHistory) 'lastCitationEditedAt': now,
          if (!shouldRecordCitationEditHistory &&
              publicData?['lastCitationEditedAt'] != null)
            'lastCitationEditedAt': publicData?['lastCitationEditedAt'],
          'favoriteCount': (publicData?['favoriteCount'] as num?)?.toInt() ?? 0,
          'ratingAverage':
              (publicData?['ratingAverage'] as num?)?.toDouble() ?? 0,
          'ratingCount': (publicData?['ratingCount'] as num?)?.toInt() ?? 0,
          'copyCount': (publicData?['copyCount'] as num?)?.toInt() ?? 0,
        }, SetOptions(merge: true));
      } else if (hasPublicMirror) {
        batch.set(publicRef, {
          'studentVisibility': lessonNoteVisibilityPrivate,
          'isDeleted': true,
          'deletedAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
      if (shouldRecordCitationEditHistory) {
        final historyRef = publicRef
            .collection(publicLessonNoteEditHistoryCollection)
            .doc();
        final compareVisibleUntil = countsTowardWeeklyLimit
            ? Timestamp.fromDate(
                nowClientUtc.add(lessonNoteCitationCompareRetentionWindow),
              )
            : null;
        batch.set(historyRef, {
          'noteId': noteId,
          'editedAt': now,
          'beforeTitle': countsTowardWeeklyLimit ? previousTitle : null,
          'beforeBody': countsTowardWeeklyLimit ? previousBody : null,
          'afterTitle': countsTowardWeeklyLimit ? draft.title : null,
          'afterBody': countsTowardWeeklyLimit ? draft.body : null,
          'countsTowardWeeklyLimit': countsTowardWeeklyLimit,
          'compareAvailable': countsTowardWeeklyLimit,
          'compareVisibleUntil': compareVisibleUntil,
        });
      }
      final staleSnapshots = staleComparisonSnapshots?.docs ?? const [];
      for (final stale in staleSnapshots) {
        if (stale.data()['compareAvailable'] != true) {
          continue;
        }
        batch.set(stale.reference, {
          'beforeTitle': FieldValue.delete(),
          'beforeBody': FieldValue.delete(),
          'afterTitle': FieldValue.delete(),
          'afterBody': FieldValue.delete(),
          'compareAvailable': false,
          'purgedAt': now,
        }, SetOptions(merge: true));
      }

      await batch.commit();
      _showMessage(
        isPublicLocked || savedVisibility == visibility
            ? savedVisibility == lessonNoteVisibilityTeacherOnly
                  ? 'メモを先生にだけ公開で保存しました。'
                  : 'メモを保存しました。'
            : visibility == lessonNoteVisibilityPublic && !platformEnabled
            ? '先生により公開メモ機能が非公開化されているため、非公開で保存しました。'
            : '音声添付またはコピー元メモは共有できないため、非公開で保存しました。',
      );
      return true;
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? 'メモの作成に失敗しました。');
      return false;
    } catch (error) {
      _showMessage('メモの作成に失敗しました: $error');
      return false;
    }
  }

  String _formatEditUnlockTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hour:$minute';
  }

  Future<void> _deleteNote(LessonNote note) async {
    if (Firebase.apps.isEmpty || note.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final publicRef = firestore.collection('publicLessonNotes').doc(note.id);
    final publicSnapshot = await _publicNoteSnapshotForDelete(
      publicRef,
      hasPublicMirror: note.hasPublicMirror,
    );
    final now = FieldValue.serverTimestamp();
    final batch = firestore.batch()
      ..set(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('lessonNotes')
            .doc(note.id),
        {'isDeleted': true, 'deletedAt': now, 'updatedAt': now},
        SetOptions(merge: true),
      );
    if (publicSnapshot?.exists ?? false) {
      batch.set(publicRef, {
        'studentVisibility': lessonNoteVisibilityPrivate,
        'isDeleted': true,
        'deletedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _publicNoteSnapshotForDelete(
    DocumentReference<Map<String, dynamic>> publicRef, {
    required bool hasPublicMirror,
  }) async {
    if (!hasPublicMirror) {
      return null;
    }
    try {
      return await publicRef.get();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  Future<_PublicSnapshotLoadResult> _publicNoteSnapshotForSave(
    DocumentReference<Map<String, dynamic>> publicRef, {
    required bool shouldRead,
  }) async {
    if (!shouldRead) {
      return const _PublicSnapshotLoadResult();
    }
    try {
      return _PublicSnapshotLoadResult(snapshot: await publicRef.get());
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const _PublicSnapshotLoadResult(permissionDenied: true);
      }
      rethrow;
    }
  }

  Future<void> _deleteFolder(
    LessonNoteFolder folder,
    _FolderDeleteMode mode,
  ) async {
    if (Firebase.apps.isEmpty || folder.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final notesSnapshot = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('lessonNotes')
        .where('folderId', isEqualTo: folder.id)
        .get();
    final batch = firestore.batch()
      ..set(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('lessonNoteFolders')
            .doc(folder.id),
        {
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    for (final noteDoc in notesSnapshot.docs) {
      if (mode == _FolderDeleteMode.deleteNotes) {
        final note = LessonNote.fromFirestore(noteDoc);
        final publicRef = firestore
            .collection('publicLessonNotes')
            .doc(noteDoc.id);
        final publicSnapshot = await _publicNoteSnapshotForDelete(
          publicRef,
          hasPublicMirror: note.hasPublicMirror,
        );
        batch.set(noteDoc.reference, {
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (publicSnapshot?.exists ?? false) {
          batch.set(publicRef, {
            'studentVisibility': lessonNoteVisibilityPrivate,
            'isDeleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } else {
        batch.set(noteDoc.reference, {
          'folderId': '',
          'folderName': '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  Future<void> _confirmDeleteNote(LessonNote note) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メモを削除'),
        content: Text('「${note.title.isEmpty ? '無題のメモ' : note.title}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await _deleteNote(note);
    }
  }

  Future<void> _confirmDeleteFolder(LessonNoteFolder folder) async {
    final mode = await showDialog<_FolderDeleteMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダを削除'),
        content: Text('「${folder.name}」内のメモをどう扱いますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_FolderDeleteMode.moveNotes),
            child: const Text('メモは残す'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_FolderDeleteMode.deleteNotes),
            child: const Text('メモも削除'),
          ),
        ],
      ),
    );
    if (mode != null) {
      await _deleteFolder(folder, mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTeacherPreview) {
      return widget.isEmbedded
          ? SizedBox(height: 420, child: _buildTeacherPreviewContent(context))
          : _buildTeacherPreviewContent(context);
    }
    return DefaultTabController(
      length: 2,
      child: widget.isEmbedded
          ? SizedBox(height: 560, child: _buildPanelContent(context))
          : _buildPanelContent(context),
    );
  }

  Widget _buildTeacherPreviewContent(BuildContext context) {
    return Card(
      margin: widget.isEmbedded ? EdgeInsets.zero : null,
      child: Padding(
        padding: widget.isEmbedded
            ? const EdgeInsets.only(top: 12)
            : EdgeInsets.zero,
        child: Column(
          children: [
            if (widget.isEmbedded) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.note_alt_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '公開メモ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('先生プレビュー中は、自分のメモを表示・作成しません。'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '公開メモを検索',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
              ),
            ),
            Expanded(child: _buildPublicNotesTab()),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelContent(BuildContext context) {
    return Card(
      margin: widget.isEmbedded ? EdgeInsets.zero : null,
      child: Padding(
        padding: widget.isEmbedded
            ? const EdgeInsets.only(top: 12)
            : EdgeInsets.zero,
        child: Column(
          children: [
            if (widget.isEmbedded) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.note_alt_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'レッスンメモ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.isEmbedded && _isEditingNote)
              Expanded(
                child: StreamBuilder<List<LessonNoteFolder>>(
                  stream: _foldersStream(),
                  builder: (context, folderSnapshot) {
                    final folders = folderSnapshot.data ?? _editingFolders;
                    return _LessonNoteEditorPage(
                      course: widget.course,
                      lesson: widget.lesson,
                      lessonNumber: widget.lessonNumber,
                      folders: folders,
                      note: _editingNote,
                      onSave: _saveNote,
                      isEmbedded: true,
                      onCancel: () {
                        setState(() {
                          _editingNote = null;
                          _isEditingNote = false;
                          _previewingOwnNote = null;
                        });
                      },
                      onSaved: () {
                        setState(() {
                          _editingNote = null;
                          _isEditingNote = false;
                          _previewingOwnNote = null;
                        });
                      },
                    );
                  },
                ),
              )
            else if (widget.isEmbedded && _previewingOwnNote != null)
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _previewingOwnNote = null;
                              });
                            },
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'メモ一覧に戻る',
                          ),
                          Text(
                            '公開メモ',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _LessonNotePreviewBody(
                        note: _previewingOwnNote!,
                        course: widget.course,
                        lesson: widget.lesson,
                        lessonNumber: widget.lessonNumber,
                        canCreateQuestion:
                            !widget.isTeacherPreview &&
                            _previewingOwnNote!.isPubliclyVisible,
                        onEdit: (_) async {
                          setState(() {
                            _editingNote = _previewingOwnNote;
                            _editingFolders = _previewFolders;
                            _previewingOwnNote = null;
                            _isEditingNote = true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const TabBar(
                tabs: [
                  Tab(text: '自分のメモ'),
                  Tab(text: '公開メモ'),
                ],
              ),
              Expanded(
                child: StreamBuilder<List<LessonNoteFolder>>(
                  stream: _foldersStream(),
                  builder: (context, folderSnapshot) {
                    final folders =
                        folderSnapshot.data ?? const <LessonNoteFolder>[];
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'メモを検索',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _query = value;
                              });
                            },
                          ),
                        ),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_message!),
                            ),
                          ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _LessonNoteList(
                                notesStream: _notesStream(),
                                folders: folders,
                                query: _query,
                                emptyText: 'このレッスンのメモはまだありません。',
                                focusedNoteId: widget.initialFocusNoteId,
                                onTap: (note) => _openOwnNotePreview(
                                  note: note,
                                  folders: folders,
                                ),
                                onDeleteNote: _confirmDeleteNote,
                                onDeleteFolder: _confirmDeleteFolder,
                                action: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () =>
                                          _openEditor(folders: folders),
                                      icon: const Icon(Icons.note_add),
                                      label: const Text('メモを作成'),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: _createFolder,
                                      icon: const Icon(Icons.create_new_folder),
                                      label: const Text('フォルダを作成'),
                                    ),
                                  ],
                                ),
                              ),
                              _buildPublicNotesTab(),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPublicNotesTab() {
    return StreamBuilder<bool>(
      stream: _notePublicPlatformEnabledStream(),
      builder: (context, platformSnapshot) {
        final enabled = platformSnapshot.data == true;
        return _LessonNoteList(
          notesStream: enabled
              ? widget.isTeacherPreview && widget.publicNotesStream == null
                    ? _teacherPreviewPublicNotesStream()
                    : _publicNotesStream()
              : Stream.value(const []),
          query: _query,
          emptyText: enabled ? '公開メモはまだありません。' : '公開メモ欄は非公開化されています。',
          onTap: _openPublicNotePreview,
          showAuthor: true,
          onToggleModeration: widget.isTeacherPreview
              ? _setPublicNoteModeration
              : null,
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<LessonNotePublicSort>(
                segments: const [
                  ButtonSegment(
                    value: LessonNotePublicSort.newest,
                    label: Text('新しい順'),
                  ),
                  ButtonSegment(
                    value: LessonNotePublicSort.popular,
                    label: Text('人気順'),
                  ),
                ],
                selected: {_publicSort},
                onSelectionChanged: enabled
                    ? (selection) {
                        setState(() {
                          _publicSort = selection.first;
                        });
                      }
                    : null,
              ),
              if (!enabled) ...[
                const SizedBox(height: 8),
                const Text('先生により、このレッスンの公開メモ欄は非公開化されています。'),
              ],
              const SizedBox(height: 8),
              const Text('コピー・評価・お気に入りは後で追加します。'),
            ],
          ),
        );
      },
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('フォルダを作成'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'フォルダ名'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('作成'),
        ),
      ],
    );
  }
}

enum _FolderDeleteMode { moveNotes, deleteNotes }

class _PublicSnapshotLoadResult {
  const _PublicSnapshotLoadResult({
    this.snapshot,
    this.permissionDenied = false,
  });

  final DocumentSnapshot<Map<String, dynamic>>? snapshot;
  final bool permissionDenied;
}

class _LessonNoteList extends StatefulWidget {
  const _LessonNoteList({
    required this.notesStream,
    required this.query,
    required this.emptyText,
    required this.action,
    required this.onTap,
    this.folders = const [],
    this.showAuthor = false,
    this.onDeleteNote,
    this.onDeleteFolder,
    this.onToggleModeration,
    this.focusedNoteId,
  });

  final Stream<List<LessonNote>> notesStream;
  final List<LessonNoteFolder> folders;
  final String query;
  final String emptyText;
  final Widget action;
  final ValueChanged<LessonNote>? onTap;
  final bool showAuthor;
  final ValueChanged<LessonNote>? onDeleteNote;
  final ValueChanged<LessonNoteFolder>? onDeleteFolder;
  final ValueChanged<LessonNote>? onToggleModeration;
  final String? focusedNoteId;

  @override
  State<_LessonNoteList> createState() => _LessonNoteListState();
}

class _LessonNoteListState extends State<_LessonNoteList> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _noteKeys = {};
  bool _didAutoScrollToFocusedNote = false;
  int _focusScrollAttemptCount = 0;

  String get _safeFocusedNoteId => (widget.focusedNoteId ?? '').trim();

  GlobalKey _noteKey(String noteId) {
    return _noteKeys.putIfAbsent(noteId, GlobalKey.new);
  }

  @override
  void didUpdateWidget(covariant _LessonNoteList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.focusedNoteId ?? '').trim() != _safeFocusedNoteId) {
      _didAutoScrollToFocusedNote = false;
      _focusScrollAttemptCount = 0;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonNote>>(
      stream: widget.notesStream,
      builder: (context, snapshot) {
        final notes = (snapshot.data ?? const <LessonNote>[])
            .where((note) => lessonNoteMatchesQuery(note, widget.query))
            .toList();
        _scheduleAutoScroll(notes);
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            widget.action,
            const SizedBox(height: 16),
            if (notes.isEmpty)
              Text(widget.emptyText)
            else if (widget.folders.isEmpty)
              for (final note in notes) _buildNoteCard(note)
            else
              ..._buildFolderSections(notes),
          ],
        );
      },
    );
  }

  Widget _buildNoteCard(LessonNote note) {
    final noteId = note.id;
    final isFocused = _safeFocusedNoteId.isNotEmpty && noteId == _safeFocusedNoteId;
    final card = _LessonNoteCard(
      key: noteId == null || noteId.isEmpty ? null : _noteKey(noteId),
      note: note,
      onTap: widget.onTap,
      showAuthor: widget.showAuthor,
      onDelete: widget.onDeleteNote,
      onToggleModeration: widget.onToggleModeration,
      isHighlighted: isFocused,
    );
    if (noteId == null || noteId.isEmpty) {
      return card;
    }
    return KeyedSubtree(
      key: ValueKey('lesson-note-card-$noteId'),
      child: card,
    );
  }

  void _scheduleAutoScroll(List<LessonNote> notes) {
    if (_didAutoScrollToFocusedNote) {
      return;
    }
    final targetId = _safeFocusedNoteId;
    if (targetId.isEmpty) {
      _didAutoScrollToFocusedNote = true;
      return;
    }
    final targetExists = notes.any((note) => note.id == targetId);
    if (!targetExists) {
      return;
    }
    final targetIndex = notes.indexWhere((note) => note.id == targetId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoScrollToFocusedNote(targetId: targetId, targetIndex: targetIndex);
    });
  }

  void _tryAutoScrollToFocusedNote({
    required String targetId,
    required int targetIndex,
  }) {
    if (!mounted || _didAutoScrollToFocusedNote) {
      return;
    }
    final targetContext = _noteKeys[targetId]?.currentContext;
    if (targetContext != null) {
      _didAutoScrollToFocusedNote = true;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
      return;
    }
    if (!_scrollController.hasClients || targetIndex < 0) {
      if (_focusScrollAttemptCount >= 8) {
        _didAutoScrollToFocusedNote = true;
        return;
      }
      _focusScrollAttemptCount += 1;
      _enqueueAutoScrollRetry(targetId: targetId, targetIndex: targetIndex);
      return;
    }
    if (_focusScrollAttemptCount >= 8) {
      _didAutoScrollToFocusedNote = true;
      return;
    }
    _focusScrollAttemptCount += 1;
    final position = _scrollController.position;
    final maxOffset = position.maxScrollExtent;
    final viewport = position.viewportDimension;
    const estimatedItemExtent = 96.0;
    final estimatedOffset =
        (targetIndex * estimatedItemExtent) - (viewport * 0.2);
    _scrollController.jumpTo(estimatedOffset.clamp(0.0, maxOffset));
    _enqueueAutoScrollRetry(targetId: targetId, targetIndex: targetIndex);
  }

  void _enqueueAutoScrollRetry({
    required String targetId,
    required int targetIndex,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoScrollToFocusedNote(targetId: targetId, targetIndex: targetIndex);
    });
  }

  List<Widget> _buildFolderSections(List<LessonNote> notes) {
    final widgets = <Widget>[];
    final notesByFolder = <String, List<LessonNote>>{};
    for (final note in notes) {
      notesByFolder.putIfAbsent(note.folderId, () => []).add(note);
    }

    for (final folder in widget.folders) {
      final folderNotes = notesByFolder.remove(folder.id ?? '') ?? const [];
      final shouldExpand = _safeFocusedNoteId.isNotEmpty &&
          folderNotes.any((note) => note.id == _safeFocusedNoteId);
      widgets.add(
        _LessonNoteFolderTile(
          folder: folder,
          notes: folderNotes,
          onDeleteFolder: widget.onDeleteFolder,
          initiallyExpanded: shouldExpand,
          noteCardBuilder: _buildNoteCard,
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }

    final unfiledNotes = notesByFolder.remove('') ?? const [];
    if (unfiledNotes.isNotEmpty) {
      widgets.add(
        _LessonNoteUnfiledSection(
          notes: unfiledNotes,
          noteCardBuilder: _buildNoteCard,
        ),
      );
    }
    for (final folderNotes in notesByFolder.values) {
      for (final note in folderNotes) {
        widgets.add(_buildNoteCard(note));
      }
    }
    return widgets;
  }
}

class _LessonNoteFolderTile extends StatelessWidget {
  const _LessonNoteFolderTile({
    required this.folder,
    required this.notes,
    required this.onDeleteFolder,
    required this.initiallyExpanded,
    required this.noteCardBuilder,
  });

  final LessonNoteFolder folder;
  final List<LessonNote> notes;
  final ValueChanged<LessonNoteFolder>? onDeleteFolder;
  final bool initiallyExpanded;
  final Widget Function(LessonNote note) noteCardBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: const Icon(Icons.folder),
        title: Text(folder.name),
        subtitle: Text('${notes.length}件のメモ'),
        trailing: IconButton(
          onPressed: onDeleteFolder == null
              ? null
              : () => onDeleteFolder!(folder),
          icon: const Icon(Icons.delete_outline),
          tooltip: 'フォルダを削除',
        ),
        children: [
          if (notes.isEmpty)
            const ListTile(title: Text('このフォルダにはメモがありません。'))
          else
            for (final note in notes) noteCardBuilder(note),
        ],
      ),
    );
  }
}

class _LessonNoteUnfiledSection extends StatelessWidget {
  const _LessonNoteUnfiledSection({
    required this.notes,
    required this.noteCardBuilder,
  });

  final List<LessonNote> notes;
  final Widget Function(LessonNote note) noteCardBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.note_outlined),
        title: const Text('フォルダなし'),
        subtitle: Text('${notes.length}件のメモ'),
        children: [for (final note in notes) noteCardBuilder(note)],
      ),
    );
  }
}

class _LessonNoteCard extends StatelessWidget {
  const _LessonNoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.showAuthor = false,
    this.onDelete,
    this.onToggleModeration,
    this.isHighlighted = false,
  });

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;
  final bool showAuthor;
  final ValueChanged<LessonNote>? onDelete;
  final ValueChanged<LessonNote>? onToggleModeration;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    if (showAuthor) {
      return _PublicLessonNoteCard(
        note: note,
        onTap: onTap,
        onToggleModeration: onToggleModeration,
      );
    }
    final highlightedBorderColor = Theme.of(context).colorScheme.primary;
    return Card(
      color: isHighlighted
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      shape: isHighlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: highlightedBorderColor, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(note),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title.isEmpty ? '無題のメモ' : note.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _noteFirstLinePreview(note.body),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: () => onDelete!(note),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'メモを削除',
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _noteToggleStatusLabel(note),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicLessonNoteCard extends StatelessWidget {
  const _PublicLessonNoteCard({
    required this.note,
    required this.onTap,
    required this.onToggleModeration,
  });

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;
  final ValueChanged<LessonNote>? onToggleModeration;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PublicUserProfile>(
      stream: publicUserProfileStream(
        userId: note.authorId,
        role: publicUserProfileRoleStudent,
        fallbackDisplayName: note.authorName,
      ),
      builder: (context, snapshot) {
        final profile =
            snapshot.data ??
            fallbackPublicUserProfile(
              userId: note.authorId,
              role: publicUserProfileRoleStudent,
              displayName: note.authorName,
            );
        return Card(
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(note),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      showPublicUserProfilePreview(
                        context: context,
                        userId: note.authorId,
                        role: publicUserProfileRoleStudent,
                        fallbackDisplayName: note.authorName,
                        isOwner: false,
                      );
                    },
                    child: PublicProfileAvatar(profile: profile),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                profile.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatPublicNoteTimestamp(note),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.title.isEmpty ? '無題のメモ' : note.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(note.body.isEmpty ? '本文なし' : note.body),
                                  if (note.tags.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(note.tags.map((tag) => '#$tag').join(' ')),
                                  ],
                                ],
                              ),
                            ),
                            if (note.hasCitationEdits && (note.id ?? '').isNotEmpty)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: InkWell(
                                  onTap: () {
                                    showPublicNoteEditHistorySheet(
                                      context,
                                      noteId: note.id!,
                                      fallbackTitle: note.title,
                                      fallbackBody: note.body,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '編集済',
                                      style: Theme.of(context).textTheme.labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onTertiaryContainer,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              note.isTeacherHidden
                                  ? '先生が非公開化中'
                                  : note.isStudentPublic
                                  ? '学習者にも公開'
                                  : '先生にだけ公開',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const Spacer(),
                            if (onToggleModeration != null)
                              TextButton(
                                onPressed: () => onToggleModeration!(note),
                                child: Text(
                                  note.isTeacherHidden ? '公開に戻す' : '非公開にする',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PublicLessonNoteDetailPage extends StatelessWidget {
  const _PublicLessonNoteDetailPage({
    required this.note,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.canCreateQuestion,
    this.onEdit,
  });

  final LessonNote note;
  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final bool canCreateQuestion;
  final Future<void> Function(BuildContext context)? onEdit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公開メモ')),
      body: SafeArea(
        child: _LessonNotePreviewBody(
          note: note,
          course: course,
          lesson: lesson,
          lessonNumber: lessonNumber,
          canCreateQuestion: canCreateQuestion,
          onEdit: onEdit,
        ),
      ),
    );
  }
}

class _LessonNotePreviewBody extends StatelessWidget {
  const _LessonNotePreviewBody({
    required this.note,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.canCreateQuestion,
    this.onEdit,
  });

  final LessonNote note;
  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final bool canCreateQuestion;
  final Future<void> Function(BuildContext context)? onEdit;

  @override
  Widget build(BuildContext context) {
    return LessonNotePreviewBody(
      note: note,
      canCreateQuestion: canCreateQuestion,
      onCreateQuestion: canCreateQuestion && note.allowsQuestionCitation
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _QuotedLessonQuestionPage(
                    course: course,
                    lesson: lesson,
                    lessonNumber: lessonNumber,
                    quotedNote: note,
                  ),
                ),
              );
            }
          : null,
      onEdit: onEdit,
    );
  }
}

class _QuotedLessonQuestionPage extends StatelessWidget {
  const _QuotedLessonQuestionPage({
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.quotedNote,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final LessonNote quotedNote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('質問コメント')),
      body: SafeArea(
        child: LessonQuestionsPanel(
          course: course,
          lesson: lesson,
          lessonNumber: lessonNumber,
          initialQuotedNote: quotedNote,
        ),
      ),
    );
  }
}

String _formatPublicNoteTimestamp(LessonNote note) {
  final timestamp = note.publicPublishedAt ?? note.createdAt ?? note.updatedAt;
  if (timestamp == null) {
    return '公開日時不明';
  }
  final dateTime = timestamp.toDate().toLocal();
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}

String _noteFirstLinePreview(String body) {
  if (body.trim().isEmpty) {
    return '本文なし';
  }
  final lines = body
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  if (lines.isEmpty) {
    return '本文なし';
  }
  return lines.first;
}

String _noteToggleStatusLabel(LessonNote note) {
  final visibilityLabel = note.isPublic
      ? 'ON'
      : note.isTeacherOnly
      ? '先生のみ'
      : 'OFF';
  final isCitationOn = note.allowsQuestionCitation ? 'ON' : 'OFF';
  return '公開:$visibilityLabel / 引用:$isCitationOn';
}

class _LessonNoteEditorPage extends StatefulWidget {
  const _LessonNoteEditorPage({
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.folders,
    required this.onSave,
    this.note,
    this.isEmbedded = false,
    this.onCancel,
    this.onSaved,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final List<LessonNoteFolder> folders;
  final LessonNote? note;
  final Future<bool> Function(_LessonNoteDraft draft) onSave;
  final bool isEmbedded;
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;

  @override
  State<_LessonNoteEditorPage> createState() => _LessonNoteEditorPageState();
}

class _LessonNoteEditorPageState extends State<_LessonNoteEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagsController;
  String _folderId = '';
  LessonNoteVisibility _visibility = LessonNoteVisibility.private;
  final Set<String> _attachmentTypes = {};
  bool _allowsQuestionCitation = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _bodyController = TextEditingController(text: note?.body ?? '');
    _tagsController = TextEditingController(
      text: note == null ? '' : note.tags.map((tag) => '#$tag').join(' '),
    );
    _folderId = note?.folderId ?? '';
    _visibility = note?.visibility ?? LessonNoteVisibility.private;
    _attachmentTypes.addAll(note?.attachmentTypes ?? const []);
    _allowsQuestionCitation = note?.allowsQuestionCitation ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  bool get _hasAudioAttachment =>
      _attachmentTypes.contains(lessonNoteAttachmentAudio);
  bool get _canPublish => canPublishLessonNote(
    hasAudioAttachment: _hasAudioAttachment,
    isCopied: widget.note?.isCopied ?? false,
    canPublish: widget.note?.canPublish ?? true,
  );

  bool get _isPublicLocked => widget.note?.visibility == LessonNoteVisibility.public;

  bool get _canChangeVisibility => _canPublish && !_isPublicLocked;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });
    LessonNoteFolder? selectedFolder;
    for (final folder in widget.folders) {
      if (folder.id == _folderId) {
        selectedFolder = folder;
        break;
      }
    }
    final saved = await widget.onSave(
      _LessonNoteDraft(
        noteId: widget.note?.id,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        folderId: selectedFolder?.id ?? '',
        folderName: selectedFolder?.name ?? '',
        visibility: _isPublicLocked
            ? LessonNoteVisibility.public
            : _canPublish
            ? _visibility
            : LessonNoteVisibility.private,
        tags: parseLessonNoteTags(_tagsController.text),
        attachmentTypes: _attachmentTypes.toList()..sort(),
        sourceNoteId: widget.note?.sourceNoteId,
        sourceAuthorId: widget.note?.sourceAuthorId,
        isCopied: widget.note?.isCopied ?? false,
        canPublish: widget.note?.canPublish ?? true,
        allowsQuestionCitation: _allowsQuestionCitation,
        wasPublic: widget.note?.visibility == LessonNoteVisibility.public,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
    });
    if (!saved) {
      return;
    }
    if (widget.isEmbedded) {
      widget.onSaved?.call();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.note == null ? 'メモを作成' : 'メモを編集';
    final form = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${widget.course.title} / レッスン${widget.lessonNumber}: ${widget.lesson.title}',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'タイトル',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyController,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '本文',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _folderId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'フォルダ',
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('フォルダなし')),
            for (final folder in widget.folders)
              DropdownMenuItem(
                value: folder.id ?? '',
                child: Text(folder.name),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _folderId = value ?? '';
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'ハッシュタグ',
            hintText: '#重要 #復習',
          ),
        ),
        const SizedBox(height: 12),
        const Text('添付予定タイプ'),
        Wrap(
          spacing: 8,
          children: [
            _AttachmentChip(
              label: 'PDF',
              value: lessonNoteAttachmentPdf,
              selected: _attachmentTypes.contains(lessonNoteAttachmentPdf),
              onSelected: _toggleAttachment,
            ),
            _AttachmentChip(
              label: '画像',
              value: lessonNoteAttachmentImage,
              selected: _attachmentTypes.contains(lessonNoteAttachmentImage),
              onSelected: _toggleAttachment,
            ),
            _AttachmentChip(
              label: '音声',
              value: lessonNoteAttachmentAudio,
              selected: _hasAudioAttachment,
              onSelected: _isPublicLocked ? null : _toggleAttachment,
            ),
          ],
        ),
        if (!_canPublish) ...[
          const SizedBox(height: 8),
          const Text('音声添付またはコピー元メモは公開できません。'),
        ],
        SwitchListTile(
          title: const Text('受講者と先生に公開する'),
          subtitle: Text(
            _isPublicLocked
                ? '一度公開したメモは後から非公開に戻せません。本文などは編集できます。'
                : '公開メモは同じ講座・レッスンのユーザーが閲覧できます。',
          ),
          value:
              (_visibility == LessonNoteVisibility.public || _isPublicLocked) &&
              _canPublish,
          onChanged: !_canChangeVisibility
              ? null
              : (value) {
                  setState(() {
                    _visibility = value
                        ? LessonNoteVisibility.public
                        : LessonNoteVisibility.private;
                  });
                },
        ),
        SwitchListTile(
          title: const Text('先生にだけ公開する'),
          subtitle: Text(
            _isPublicLocked
                ? '一度受講者にも公開したメモは、先生だけ公開に戻せません。'
                : 'オンの場合は先生だけが閲覧できます。',
          ),
          value: _visibility == LessonNoteVisibility.teacherOnly && _canPublish,
          onChanged:
              !_canPublish ||
                  _isPublicLocked ||
                  _visibility == LessonNoteVisibility.public
              ? null
              : (value) {
                  setState(() {
                    _visibility = value
                        ? LessonNoteVisibility.teacherOnly
                        : LessonNoteVisibility.private;
                  });
                },
        ),
        SwitchListTile(
          title: const Text('質問での引用を許可する'),
          subtitle: Text(
            _allowsQuestionCitation
                ? '一度許可した引用は後から取り消せません。'
                : '許可すると、他の学習者がこの公開メモを引用して質問できます。',
          ),
          value: _allowsQuestionCitation,
          onChanged: !_canPublish || _allowsQuestionCitation
              ? null
              : (value) {
                  setState(() {
                    _allowsQuestionCitation = value;
                  });
                },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: Icon(widget.note == null ? Icons.add : Icons.save),
          label: Text(widget.note == null ? '作成' : '保存'),
        ),
      ],
    );

    if (widget.isEmbedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'メモ一覧に戻る',
                ),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Expanded(child: form),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: form,
    );
  }

  void _toggleAttachment(String value, bool selected) {
    setState(() {
      if (selected) {
        if (_isPublicLocked && value == lessonNoteAttachmentAudio) {
          return;
        }
        _attachmentTypes.add(value);
        if (value == lessonNoteAttachmentAudio) {
          _visibility = LessonNoteVisibility.private;
        }
      } else {
        _attachmentTypes.remove(value);
      }
    });
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool selected;
  final void Function(String value, bool selected)? onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected == null
          ? null
          : (selected) => onSelected!(value, selected),
    );
  }
}

class _LessonNoteDraft {
  const _LessonNoteDraft({
    required this.noteId,
    required this.title,
    required this.body,
    required this.folderId,
    required this.folderName,
    required this.visibility,
    required this.tags,
    required this.attachmentTypes,
    required this.sourceNoteId,
    required this.sourceAuthorId,
    required this.isCopied,
    required this.canPublish,
    required this.allowsQuestionCitation,
    required this.wasPublic,
  });

  final String? noteId;
  final String title;
  final String body;
  final String folderId;
  final String folderName;
  final LessonNoteVisibility visibility;
  final List<String> tags;
  final List<String> attachmentTypes;
  final String? sourceNoteId;
  final String? sourceAuthorId;
  final bool isCopied;
  final bool canPublish;
  final bool allowsQuestionCitation;
  final bool wasPublic;
}
