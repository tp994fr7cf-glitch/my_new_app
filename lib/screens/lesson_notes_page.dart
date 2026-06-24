import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_participant_identity.dart';
import '../models/lesson_note.dart';
import '../models/public_user_profile.dart';
import '../services/course_identity_service.dart';
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
    this.teacherHiddenOwnNoteIdsStream,
    this.publicRestrictionModeStream,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonNote>>? notesStream;
  final Stream<List<LessonNote>>? publicNotesStream;
  final Stream<List<LessonNoteFolder>>? foldersStream;
  final String? initialFocusNoteId;
  final Stream<Set<String>>? teacherHiddenOwnNoteIdsStream;
  final Stream<String>? publicRestrictionModeStream;

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
        teacherHiddenOwnNoteIdsStream: teacherHiddenOwnNoteIdsStream,
        publicRestrictionModeStream: publicRestrictionModeStream,
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
    this.teacherHiddenOwnNoteIdsStream,
    this.publicRestrictionModeStream,
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
  final Stream<Set<String>>? teacherHiddenOwnNoteIdsStream;
  final Stream<String>? publicRestrictionModeStream;

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
  Stream<List<LessonNote>>? _providedNotesSource;
  Stream<List<LessonNote>>? _providedNotesBroadcast;
  Stream<List<LessonNote>>? _providedPublicNotesSource;
  Stream<List<LessonNote>>? _providedPublicNotesBroadcast;
  Stream<String>? _cachedLearnerRestrictionModeStream;
  Object? _cachedLearnerRestrictionModeStreamKey;
  LessonNotePublicSort _ownSort = LessonNotePublicSort.newest;
  LessonNotePublicSort _publicSort = LessonNotePublicSort.newest;
  bool _lastKnownNotePublicPlatformEnabled = true;
  final Set<String> _processingPublicApprovalNoteIds = <String>{};
  final Set<String> _suppressedPublicApprovalBellNoteIds = <String>{};
  final LessonInteractionService _lessonInteractionService =
      const LessonInteractionService();
  final CourseIdentityService _courseIdentityService =
      const CourseIdentityService();

  String get _courseId => widget.course.storageId;

  String get _interactionSettingId =>
      _lessonInteractionService.settingDocumentId(
        courseId: _courseId,
        lessonNumber: widget.lessonNumber,
      );

  String? get _currentUserId =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;

  bool get _isCurrentUserInstructor {
    final userId = _currentUserId;
    return userId != null &&
        userId.isNotEmpty &&
        widget.course.instructorId == userId;
  }

  Stream<String> _learnerRestrictionModeStream() {
    final cacheKey = Object.hash(
      widget.publicRestrictionModeStream,
      widget.lessonNumber,
      _currentUserId,
      widget.isTeacherPreview,
      _isCurrentUserInstructor,
      _courseId,
    );
    if (_cachedLearnerRestrictionModeStream != null &&
        _cachedLearnerRestrictionModeStreamKey == cacheKey) {
      return _cachedLearnerRestrictionModeStream!;
    }
    final provided = widget.publicRestrictionModeStream;
    late final Stream<String> stream;
    if (provided != null) {
      stream = provided.map(
        _lessonInteractionService.normalizeLearnerRestrictionMode,
      );
    } else {
      final userId = _currentUserId;
      if (widget.isTeacherPreview ||
          _isCurrentUserInstructor ||
          userId == null ||
          userId.isEmpty) {
        stream = Stream.value(
          LessonInteractionService.learnerRestrictionModeNone,
        );
      } else {
        stream = _lessonInteractionService.learnerRestrictionModeStream(
          courseId: _courseId,
          lessonNumber: widget.lessonNumber,
          learnerId: userId,
        );
      }
    }
    final broadcast = stream.asBroadcastStream();
    _cachedLearnerRestrictionModeStream = broadcast;
    _cachedLearnerRestrictionModeStreamKey = cacheKey;
    return broadcast;
  }

  Future<String> _currentLearnerRestrictionMode() async {
    final userId = _currentUserId;
    if (widget.isTeacherPreview ||
        _isCurrentUserInstructor ||
        userId == null ||
        userId.isEmpty) {
      return LessonInteractionService.learnerRestrictionModeNone;
    }
    return _lessonInteractionService.learnerRestrictionMode(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      learnerId: userId,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<LessonNote>> _asBroadcastNotesStream(
    Stream<List<LessonNote>> source, {
    required bool isPublic,
  }) {
    if (isPublic) {
      if (!identical(source, _providedPublicNotesSource)) {
        _providedPublicNotesSource = source;
        _providedPublicNotesBroadcast = source.asBroadcastStream();
      }
      return _providedPublicNotesBroadcast!;
    }
    if (!identical(source, _providedNotesSource)) {
      _providedNotesSource = source;
      _providedNotesBroadcast = source.asBroadcastStream();
    }
    return _providedNotesBroadcast!;
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
      return _asBroadcastNotesStream(provided, isPublic: false).map(
        (notes) => sortLessonNotes(
          notes.where((note) => !note.isDeleted).toList(),
          _ownSort,
        ),
      );
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
          return sortLessonNotes(
            snapshot.docs
                .map(LessonNote.fromFirestore)
                .where((note) => !note.isDeleted)
                .toList(),
            _ownSort,
          );
        });
  }

  Stream<Set<String>> _teacherHiddenOwnNoteIdsStream() {
    final provided = widget.teacherHiddenOwnNoteIdsStream;
    if (provided != null) {
      return provided;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const <String>{});
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const <String>{});
    }

    return FirebaseFirestore.instance
        .collection('publicLessonNotes')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .where('interactionSettingId', isEqualTo: _interactionSettingId)
        .where('authorId', isEqualTo: user.uid)
        .where(
          'moderationStatus',
          isEqualTo: lessonNoteModerationHiddenByTeacher,
        )
        .where('isDeleted', isEqualTo: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  Stream<List<LessonNote>> _publicNotesStream() {
    final provided = widget.publicNotesStream;
    if (provided != null) {
      return _asBroadcastNotesStream(provided, isPublic: true).map((notes) {
        final filtered = widget.isTeacherPreview
            ? notes.where((note) => !note.isDeleted).toList()
            : notes.where((note) => note.isPubliclyVisible).toList();
        return sortPublicLessonNotes(filtered, _publicSort);
      });
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
    return _lessonInteractionService
        .publicFeatureEnabledStream(
          courseId: _courseId,
          lessonNumber: widget.lessonNumber,
          fieldName: LessonInteractionService.lessonNotesPublicEnabledField,
        )
        .map((enabled) {
          _lastKnownNotePublicPlatformEnabled = enabled;
          return enabled;
        });
  }

  Future<bool> _isNotePublicPlatformEnabled() async {
    return _lessonInteractionService.isPublicFeatureEnabled(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonNotesPublicEnabledField,
    );
  }

  Future<CourseParticipantIdentity> _loadParticipantIdentity(
    String learnerId,
  ) async {
    final safeLearnerId = learnerId.trim();
    if (Firebase.apps.isEmpty || safeLearnerId.isEmpty) {
      return CourseParticipantIdentity(
        courseId: _courseId,
        userId: safeLearnerId,
        identityMode: courseIdentityModeProfile,
        aliasConfiguredAtEnrollment: false,
        aliasRetired: false,
      );
    }
    final doc = await FirebaseFirestore.instance
        .collection('courses')
        .doc(_courseId)
        .collection('participantIdentities')
        .doc(safeLearnerId)
        .get();
    if (doc.exists) {
      return CourseParticipantIdentity.fromFirestore(doc);
    }
    return CourseParticipantIdentity(
      courseId: _courseId,
      userId: safeLearnerId,
      identityMode: courseIdentityModeProfile,
      aliasConfiguredAtEnrollment: false,
      aliasRetired: false,
    );
  }

  Future<void> _openRestrictionDetailsFromNote(LessonNote note) async {
    if (!widget.isTeacherPreview) {
      return;
    }
    final learnerId = note.authorId.trim();
    if (learnerId.isEmpty) {
      _showMessage('受講者情報を特定できないため設定を開けません。');
      return;
    }
    if (learnerId == widget.course.instructorId) {
      _showMessage('先生投稿は受講者制限の対象外です。');
      return;
    }
    final identity = await _loadParticipantIdentity(learnerId);
    final currentMode = await _lessonInteractionService.learnerRestrictionMode(
      courseId: _courseId,
      lessonNumber: note.lessonNumber,
      learnerId: identity.userId,
    );
    if (!mounted) {
      return;
    }
    await _openLearnerRestrictionDialog(
      lessonNumber: note.lessonNumber,
      identity: identity,
      currentMode: currentMode,
    );
  }

  Future<void> _openLearnerRestrictionDialog({
    required int lessonNumber,
    required CourseParticipantIdentity identity,
    required String currentMode,
  }) async {
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final currentlyBulkHidden = await _lessonInteractionService
        .hasBulkHiddenPublicPosts(
          courseId: _courseId,
          lessonNumber: lessonNumber,
          learnerId: identity.userId,
        );
    var selectedMode = _lessonInteractionService
        .normalizeLearnerRestrictionMode(currentMode);
    var bulkHide = currentlyBulkHidden;
    var bulkUnhide = false;
    var bulkUnhidePolicy =
        LessonInteractionService.bulkUnhideKeepIndividualHidden;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('非公開詳細設定'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('対象ユーザー: ${identity.userId}'),
                    const SizedBox(height: 8),
                    Text('レッスン$lessonNumber'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '制限モード',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: LessonInteractionService
                              .learnerRestrictionModeNone,
                          child: Text('制限なし'),
                        ),
                        DropdownMenuItem(
                          value: LessonInteractionService
                              .learnerRestrictionModeNoPublicReadOrPost,
                          child: Text('公開欄の閲覧と投稿を制限'),
                        ),
                        DropdownMenuItem(
                          value: LessonInteractionService
                              .learnerRestrictionModeNoPublicPost,
                          child: Text('公開欄への投稿のみ制限'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedMode = _lessonInteractionService
                              .normalizeLearnerRestrictionMode(value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: bulkHide,
                      title: const Text('既存公開投稿を一括で非公開にする'),
                      onChanged: (value) {
                        setDialogState(() {
                          bulkHide = value == true;
                          if (bulkHide) {
                            bulkUnhide = false;
                          }
                        });
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: bulkUnhide,
                      title: const Text('既存公開投稿を一括で公開に戻す'),
                      onChanged: (value) {
                        setDialogState(() {
                          bulkUnhide = value == true;
                          if (bulkUnhide) {
                            bulkHide = false;
                          }
                        });
                      },
                    ),
                    if (bulkUnhide) ...[
                      const SizedBox(height: 8),
                      const Text('一括公開の方針'),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: LessonInteractionService
                            .bulkUnhideKeepIndividualHidden,
                        groupValue: bulkUnhidePolicy,
                        title: const Text('A: 個別非公開は維持'),
                        onChanged: (value) {
                          setDialogState(() {
                            bulkUnhidePolicy =
                                value ??
                                LessonInteractionService
                                    .bulkUnhideKeepIndividualHidden;
                          });
                        },
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value:
                            LessonInteractionService.bulkUnhideForceAllVisible,
                        groupValue: bulkUnhidePolicy,
                        title: const Text('B: すべて公開に戻す'),
                        onChanged: (value) {
                          setDialogState(() {
                            bulkUnhidePolicy =
                                value ??
                                LessonInteractionService
                                    .bulkUnhideKeepIndividualHidden;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('保存する'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _lessonInteractionService.setLearnerRestrictionMode(
        courseId: _courseId,
        lessonNumber: lessonNumber,
        learnerId: identity.userId,
        restrictionMode: selectedMode,
        updatedByUserId: user.uid,
      );
      var affected = 0;
      if (bulkHide) {
        affected = await _lessonInteractionService
            .setBulkModerationForLearnerPublicPosts(
              courseId: _courseId,
              lessonNumber: lessonNumber,
              learnerId: identity.userId,
              hide: true,
            );
      } else if (bulkUnhide) {
        affected = await _lessonInteractionService
            .setBulkModerationForLearnerPublicPosts(
              courseId: _courseId,
              lessonNumber: lessonNumber,
              learnerId: identity.userId,
              hide: false,
              unhidePolicy: bulkUnhidePolicy,
            );
      }
      _showMessage(
        affected > 0 ? '設定を保存しました。公開状態更新: $affected件' : '設定を保存しました。',
      );
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? '設定の保存に失敗しました。');
    } catch (error) {
      _showMessage('設定の保存に失敗しました: $error');
    }
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

  Future<void> _handleOwnPublicApprovalNoticeTap(LessonNote note) async {
    if (note.isPublicApprovalPending) {
      await _showPublicApprovalMessageDialog('現在先生に許可申請中です。');
      return;
    }
    if (!note.isPublicApprovalRejected) {
      return;
    }
    await _showPublicApprovalMessageDialog('このメモの公開は許可されませんでした。');
    if (!mounted) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      return;
    }
    final noteId = note.id;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (noteId == null || userId == null || userId.isEmpty) {
      return;
    }
    try {
      await _lessonInteractionService.clearOwnPublicApprovalNotice(
        noteId: noteId,
        ownerId: userId,
      );
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? '通知状態の更新に失敗しました。');
    } catch (error) {
      _showMessage('通知状態の更新に失敗しました: $error');
    }
  }

  Future<void> _handleTeacherPublicApprovalTap(LessonNote note) async {
    final noteId = note.id;
    if (noteId == null || noteId.isEmpty) {
      return;
    }
    if (_processingPublicApprovalNoteIds.contains(noteId)) {
      _showMessage('公開処理を実行中です。完了までお待ちください。');
      return;
    }
    if (!note.isPublicApprovalPending) {
      _showMessage('この申請はすでに処理済みです。');
      return;
    }
    if (Firebase.apps.isNotEmpty) {
      try {
        final latestSnapshot = await FirebaseFirestore.instance
            .collection('publicLessonNotes')
            .doc(noteId)
            .get();
        if (!latestSnapshot.exists) {
          _showMessage('申請対象のメモが見つかりませんでした。画面を更新してください。');
          return;
        }
        final latestNote = LessonNote.fromFirestore(latestSnapshot);
        if (!latestNote.isPublicApprovalPending) {
          _showMessage(
            latestNote.isStudentPublic
                ? 'このメモはすでに公開済みです。'
                : latestNote.isPublicApprovalRejected
                ? 'この申請はすでに「許可しない」で処理されています。'
                : 'この申請はすでに処理済みです。',
          );
          setState(() {
            _suppressedPublicApprovalBellNoteIds.add(noteId);
          });
          _releaseSuppressedApprovalBellLater(noteId);
          return;
        }
      } on FirebaseException catch (_) {
        // If latest-check fails temporarily, keep the original flow.
      }
    }
    if (!mounted) {
      return;
    }
    final decision = await showDialog<_PublicApprovalDecision>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('このメモを受講者にも公開しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_PublicApprovalDecision.reject),
            child: const Text('許可しない'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_PublicApprovalDecision.approve),
            child: const Text('許可'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) {
      return;
    }
    setState(() {
      _processingPublicApprovalNoteIds.add(noteId);
      _suppressedPublicApprovalBellNoteIds.add(noteId);
    });
    _showMessage('公開処理中です。しばらくお待ちください。');
    var keepBellSuppressed = true;
    try {
      await _lessonInteractionService.decidePublicNoteApproval(
        noteId: noteId,
        authorId: note.authorId,
        approve: decision == _PublicApprovalDecision.approve,
      );
      _showMessage(
        decision == _PublicApprovalDecision.approve
            ? '公開を許可しました。反映まで少し時間がかかる場合があります。'
            : '公開を許可しませんでした。',
      );
    } on FirebaseException catch (error) {
      keepBellSuppressed = false;
      _showMessage(_friendlyPublicApprovalErrorMessage(error));
    } catch (error) {
      keepBellSuppressed = false;
      _showMessage('公開許可の更新に失敗しました: $error');
    } finally {
      if (mounted) {
        setState(() {
          _processingPublicApprovalNoteIds.remove(noteId);
          if (!keepBellSuppressed) {
            _suppressedPublicApprovalBellNoteIds.remove(noteId);
          }
        });
        if (keepBellSuppressed) {
          _releaseSuppressedApprovalBellLater(noteId);
        }
      }
    }
  }

  String _friendlyPublicApprovalErrorMessage(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' =>
        error.message ?? '公開許可を実行できませんでした。権限設定または申請データの状態を確認して、もう一度お試しください。',
      'failed-precondition' => error.message ?? 'この申請はすでに処理済みです。画面を更新してください。',
      _ => error.message ?? '公開許可の更新に失敗しました。',
    };
  }

  bool _isPublicApprovalProcessing(LessonNote note) {
    final noteId = note.id;
    if (noteId == null || noteId.isEmpty) {
      return false;
    }
    return _processingPublicApprovalNoteIds.contains(noteId);
  }

  bool _isPublicApprovalBellSuppressed(LessonNote note) {
    final noteId = note.id;
    if (noteId == null || noteId.isEmpty) {
      return false;
    }
    final suppressed = _suppressedPublicApprovalBellNoteIds.contains(noteId);
    if (suppressed && !note.isPublicApprovalPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _suppressedPublicApprovalBellNoteIds.remove(noteId);
        });
      });
      return false;
    }
    return suppressed;
  }

  void _releaseSuppressedApprovalBellLater(String noteId) {
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _suppressedPublicApprovalBellNoteIds.remove(noteId);
      });
    });
  }

  Future<void> _showPublicApprovalMessageDialog(String message) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
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
    await _pushEditorPage(context, note: note, folders: folders);
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

    DocumentReference<Map<String, dynamic>>? noteRefForApprovalRaceCheck;
    DocumentReference<Map<String, dynamic>>? publicRefForApprovalRaceCheck;
    var cancelPublicApprovalRequested = false;

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final noteRef = draft.noteId == null
          ? userRef.collection('lessonNotes').doc()
          : userRef.collection('lessonNotes').doc(draft.noteId);
      noteRefForApprovalRaceCheck = noteRef;
      final noteId = noteRef.id;
      final nowClientUtc = DateTime.now().toUtc();
      final visibility = draft.visibility == LessonNoteVisibility.public
          ? lessonNoteVisibilityPublic
          : draft.visibility == LessonNoteVisibility.teacherOnly
          ? lessonNoteVisibilityTeacherOnly
          : lessonNoteVisibilityPrivate;
      final restrictionMode = await _currentLearnerRestrictionMode();
      final blocksPublicPost = _lessonInteractionService.blocksPublicPost(
        restrictionMode,
      );
      if (blocksPublicPost && visibility == lessonNoteVisibilityPublic) {
        _showMessage('先生により公開メモへの投稿が制限されています。非公開または先生のみ公開で保存してください。');
        return false;
      }
      final now = FieldValue.serverTimestamp();
      final authorName = user.displayName ?? user.email ?? '学習者';
      final courseInstructorId = widget.course.instructorId?.trim() ?? '';
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
      final isTeacherOnlyLocked = !isPublicLocked && draft.wasTeacherOnly;
      final requestedPublicApproval =
          draft.requestPublicApproval &&
          visibility == lessonNoteVisibilityPublic &&
          canPublish &&
          platformEnabled;
      final savedVisibility = isPublicLocked
          ? lessonNoteVisibilityPublic
          : isTeacherOnlyLocked
          ? lessonNoteVisibilityTeacherOnly
          : switch (visibility) {
              lessonNoteVisibilityPublic =>
                canPublish && platformEnabled
                    ? lessonNoteVisibilityPublic
                    : lessonNoteVisibilityPrivate,
              lessonNoteVisibilityTeacherOnly =>
                canPublish
                    ? lessonNoteVisibilityTeacherOnly
                    : lessonNoteVisibilityPrivate,
              _ => lessonNoteVisibilityPrivate,
            };
      final publicRef = firestore.collection('publicLessonNotes').doc(noteId);
      publicRefForApprovalRaceCheck = publicRef;
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
      final existingPublicApprovalStatusFromOwner =
          normalizeLessonNotePublicApprovalStatus(
            existingData?['publicApprovalStatus'] as String?,
          );
      final existingPublicApprovalStatusFromMirror =
          normalizeLessonNotePublicApprovalStatus(
            publicData?['publicApprovalStatus'] as String?,
          );
      final existingPublicApprovalStatus =
          resolveLessonNotePublicApprovalStatus(
            ownerPublicApprovalStatus: existingPublicApprovalStatusFromOwner,
            mirrorPublicApprovalStatus: existingPublicApprovalStatusFromMirror,
          );
      cancelPublicApprovalRequested =
          draft.wasPublicApprovalPending && !draft.requestPublicApproval;
      final approvedByTeacherAlready = isLessonNoteAlreadyApprovedByTeacher(
        ownerPublicApprovalStatus:
            existingData?['publicApprovalStatus'] as String?,
        ownerVisibility: existingData?['visibility'] as String?,
        mirrorPublicApprovalStatus:
            publicData?['publicApprovalStatus'] as String?,
        mirrorStudentVisibility: publicData?['studentVisibility'] as String?,
      );
      if (cancelPublicApprovalRequested && approvedByTeacherAlready) {
        await _showPublicApprovalMessageDialog('先生により既に許可されています。');
        return false;
      }
      final nextPublicApprovalStatus = switch (savedVisibility) {
        lessonNoteVisibilityPrivate => lessonNotePublicApprovalNone,
        lessonNoteVisibilityPublic => lessonNotePublicApprovalNone,
        _ =>
          cancelPublicApprovalRequested
              ? lessonNotePublicApprovalNone
              : requestedPublicApproval
              ? lessonNotePublicApprovalPending
              : existingPublicApprovalStatus == lessonNotePublicApprovalApproved
              ? lessonNotePublicApprovalNone
              : existingPublicApprovalStatus,
      };
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
                            existingData?['citationFreeEditUntil']
                                as Timestamp?,
                        publicPublishedAt:
                            (existingData?['publicPublishedAt']
                                as Timestamp?) ??
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
      final authorSnapshot = await _courseIdentityService.resolveAuthorSnapshot(
        courseId: _courseId,
        userId: user.uid,
        fallbackDisplayName: authorName,
        role: publicUserProfileRoleStudent,
      );
      final data = {
        'userId': user.uid,
        'authorId': user.uid,
        'authorName': authorSnapshot.displayName,
        'authorAvatarColorName': authorSnapshot.avatarColorName,
        'authorProfileVisible': authorSnapshot.profileVisible,
        'authorIdentityMode': authorSnapshot.identityMode,
        'title': draft.title,
        'body': draft.body,
        'folderId': draft.folderId,
        'folderName': draft.folderName,
        'courseId': _courseId,
        'courseTitle': widget.course.title,
        'lessonNumber': widget.lessonNumber,
        'lessonTitle': widget.lesson.title,
        if (courseInstructorId.isNotEmpty) 'instructorId': courseInstructorId,
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
        if (draft.allowsQuestionCitation)
          'citationEnabledAt': citationEnabledAt,
        if (draft.allowsQuestionCitation)
          'citationFreeEditUntil': citationFreeEditUntil,
        if (draft.allowsQuestionCitation)
          'citationEditCount': nextCitationEditCount,
        if (shouldRecordCitationEditHistory) 'lastCitationEditedAt': now,
        if (!shouldRecordCitationEditHistory &&
            existingData?['lastCitationEditedAt'] != null)
          'lastCitationEditedAt': existingData?['lastCitationEditedAt'],
        'publicApprovalStatus': nextPublicApprovalStatus,
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
          if (draft.allowsQuestionCitation)
            'citationEnabledAt': citationEnabledAt,
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
          'publicApprovalStatus': lessonNotePublicApprovalNone,
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
      if (cancelPublicApprovalRequested) {
        await _showPublicApprovalMessageDialog('公開許可の申請を取り下げました。');
        return true;
      }
      _showMessage(
        requestedPublicApproval
            ? '先生への公開申請を送信しました。許可されるまで受講者には公開されません。'
            : isPublicLocked ||
                  isTeacherOnlyLocked ||
                  savedVisibility == visibility
            ? savedVisibility == lessonNoteVisibilityTeacherOnly
                  ? 'メモを先生にだけ公開で保存しました。'
                  : 'メモを保存しました。'
            : visibility == lessonNoteVisibilityPublic && !platformEnabled
            ? '先生により公開メモ機能が非公開化されているため、非公開で保存しました。'
            : '音声添付またはコピー元メモは共有できないため、非公開で保存しました。',
      );
      return true;
    } on FirebaseException catch (error) {
      final shouldRetryForApprovalRace =
          cancelPublicApprovalRequested &&
          noteRefForApprovalRaceCheck != null &&
          publicRefForApprovalRaceCheck != null &&
          (error.code == 'permission-denied' ||
              error.code == 'aborted' ||
              error.code == 'failed-precondition');
      if (shouldRetryForApprovalRace) {
        final approvedByTeacherNow = await _isNoteApprovedByTeacherNow(
          noteRef: noteRefForApprovalRaceCheck,
          publicRef: publicRefForApprovalRaceCheck,
        );
        if (approvedByTeacherNow) {
          await _showPublicApprovalMessageDialog('先生により既に許可されています。');
          return false;
        }
      }
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

  Future<bool> _isNoteApprovedByTeacherNow({
    required DocumentReference<Map<String, dynamic>> noteRef,
    required DocumentReference<Map<String, dynamic>> publicRef,
  }) async {
    final ownerSnapshot = await noteRef.get();
    final ownerData = ownerSnapshot.data();
    Map<String, dynamic>? publicData;
    try {
      final publicSnapshot = await publicRef.get();
      publicData = publicSnapshot.data();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
    }
    return isLessonNoteAlreadyApprovedByTeacher(
      ownerPublicApprovalStatus: ownerData?['publicApprovalStatus'] as String?,
      ownerVisibility: ownerData?['visibility'] as String?,
      mirrorPublicApprovalStatus:
          publicData?['publicApprovalStatus'] as String?,
      mirrorStudentVisibility: publicData?['studentVisibility'] as String?,
    );
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
                              StreamBuilder<Set<String>>(
                                stream: _teacherHiddenOwnNoteIdsStream(),
                                builder: (context, hiddenSnapshot) {
                                  final hiddenOwnNoteIds =
                                      hiddenSnapshot.data ?? const <String>{};
                                  return _LessonNoteList(
                                    notesStream: _notesStream(),
                                    folders: folders,
                                    query: _query,
                                    emptyText: 'このレッスンのメモはまだありません。',
                                    focusedNoteId: widget.initialFocusNoteId,
                                    teacherHiddenNoteIds: hiddenOwnNoteIds,
                                    onTap: (note) => _openOwnNotePreview(
                                      note: note,
                                      folders: folders,
                                    ),
                                    onDeleteNote: _confirmDeleteNote,
                                    onDeleteFolder: _confirmDeleteFolder,
                                    onApprovalNoticeTap:
                                        _handleOwnPublicApprovalNoticeTap,
                                    action: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SegmentedButton<LessonNotePublicSort>(
                                          segments: const [
                                            ButtonSegment(
                                              value:
                                                  LessonNotePublicSort.newest,
                                              label: Text('新しい順'),
                                            ),
                                            ButtonSegment(
                                              value:
                                                  LessonNotePublicSort.popular,
                                              label: Text('人気順'),
                                            ),
                                            ButtonSegment(
                                              value: LessonNotePublicSort
                                                  .editedNewest,
                                              label: Text('編集の新しい順'),
                                            ),
                                          ],
                                          selected: {_ownSort},
                                          onSelectionChanged: (selection) {
                                            setState(() {
                                              _ownSort = selection.first;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        FilledButton.icon(
                                          onPressed: () =>
                                              _openEditor(folders: folders),
                                          icon: const Icon(Icons.note_add),
                                          label: const Text('メモを作成'),
                                        ),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                          onPressed: _createFolder,
                                          icon: const Icon(
                                            Icons.create_new_folder,
                                          ),
                                          label: const Text('フォルダを作成'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
        final enabled =
            platformSnapshot.data ?? _lastKnownNotePublicPlatformEnabled;
        return StreamBuilder<String>(
          stream: _learnerRestrictionModeStream(),
          builder: (context, restrictionSnapshot) {
            final restrictionMode =
                restrictionSnapshot.data ??
                LessonInteractionService.learnerRestrictionModeNone;
            final blocksPublicRead = _lessonInteractionService.blocksPublicRead(
              restrictionMode,
            );
            final canReadPublic = enabled && !blocksPublicRead;
            return _LessonNoteList(
              notesStream: canReadPublic
                  ? widget.isTeacherPreview && widget.publicNotesStream == null
                        ? _teacherPreviewPublicNotesStream()
                        : _publicNotesStream()
                  : Stream.value(const []),
              query: _query,
              emptyText: !enabled
                  ? '公開メモ欄は非公開化されています。'
                  : blocksPublicRead
                  ? '先生により公開メモの閲覧が制限されています。'
                  : '公開メモはまだありません。',
              onTap: _openPublicNotePreview,
              showAuthor: true,
              onToggleModeration: widget.isTeacherPreview
                  ? _setPublicNoteModeration
                  : null,
              onOpenRestrictionSettings: widget.isTeacherPreview
                  ? _openRestrictionDetailsFromNote
                  : null,
              onResolvePublicApproval: widget.isTeacherPreview
                  ? _handleTeacherPublicApprovalTap
                  : null,
              isPublicApprovalProcessing: widget.isTeacherPreview
                  ? _isPublicApprovalProcessing
                  : null,
              isPublicApprovalBellSuppressed: widget.isTeacherPreview
                  ? _isPublicApprovalBellSuppressed
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
                      ButtonSegment(
                        value: LessonNotePublicSort.editedNewest,
                        label: Text('編集の新しい順'),
                      ),
                    ],
                    selected: {_publicSort},
                    onSelectionChanged: canReadPublic
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
                  if (blocksPublicRead) ...[
                    const SizedBox(height: 8),
                    const Text('先生により、このレッスンの公開メモ閲覧は制限されています。'),
                  ],
                  const SizedBox(height: 8),
                  const Text('コピー・評価・お気に入りは後で追加します。'),
                ],
              ),
            );
          },
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
    this.onOpenRestrictionSettings,
    this.onApprovalNoticeTap,
    this.onResolvePublicApproval,
    this.isPublicApprovalProcessing,
    this.isPublicApprovalBellSuppressed,
    this.focusedNoteId,
    this.teacherHiddenNoteIds = const <String>{},
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
  final ValueChanged<LessonNote>? onOpenRestrictionSettings;
  final ValueChanged<LessonNote>? onApprovalNoticeTap;
  final ValueChanged<LessonNote>? onResolvePublicApproval;
  final bool Function(LessonNote note)? isPublicApprovalProcessing;
  final bool Function(LessonNote note)? isPublicApprovalBellSuppressed;
  final String? focusedNoteId;
  final Set<String> teacherHiddenNoteIds;

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
    final isFocused =
        _safeFocusedNoteId.isNotEmpty && noteId == _safeFocusedNoteId;
    final showTeacherHiddenNotice =
        noteId != null &&
        noteId.isNotEmpty &&
        widget.teacherHiddenNoteIds.contains(noteId);
    final card = _LessonNoteCard(
      key: noteId == null || noteId.isEmpty ? null : _noteKey(noteId),
      note: note,
      onTap: widget.onTap,
      showAuthor: widget.showAuthor,
      showTeacherHiddenNotice: showTeacherHiddenNotice,
      onDelete: widget.onDeleteNote,
      onToggleModeration: widget.onToggleModeration,
      onOpenRestrictionSettings: widget.onOpenRestrictionSettings,
      onApprovalNoticeTap: widget.onApprovalNoticeTap,
      onResolvePublicApproval: widget.onResolvePublicApproval,
      isPublicApprovalProcessing:
          widget.isPublicApprovalProcessing?.call(note) ?? false,
      suppressPublicApprovalBell:
          widget.isPublicApprovalBellSuppressed?.call(note) ?? false,
      isHighlighted: isFocused,
    );
    if (noteId == null || noteId.isEmpty) {
      return card;
    }
    return KeyedSubtree(key: ValueKey('lesson-note-card-$noteId'), child: card);
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
      final shouldExpand =
          _safeFocusedNoteId.isNotEmpty &&
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
    this.showTeacherHiddenNotice = false,
    this.onDelete,
    this.onToggleModeration,
    this.onOpenRestrictionSettings,
    this.onApprovalNoticeTap,
    this.onResolvePublicApproval,
    this.isPublicApprovalProcessing = false,
    this.suppressPublicApprovalBell = false,
    this.isHighlighted = false,
  });

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;
  final bool showAuthor;
  final bool showTeacherHiddenNotice;
  final ValueChanged<LessonNote>? onDelete;
  final ValueChanged<LessonNote>? onToggleModeration;
  final ValueChanged<LessonNote>? onOpenRestrictionSettings;
  final ValueChanged<LessonNote>? onApprovalNoticeTap;
  final ValueChanged<LessonNote>? onResolvePublicApproval;
  final bool isPublicApprovalProcessing;
  final bool suppressPublicApprovalBell;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    if (showAuthor) {
      return _PublicLessonNoteCard(
        note: note,
        onTap: onTap,
        onToggleModeration: onToggleModeration,
        onOpenRestrictionSettings: onOpenRestrictionSettings,
        onResolvePublicApproval: onResolvePublicApproval,
        isPublicApprovalProcessing: isPublicApprovalProcessing,
        suppressPublicApprovalBell: suppressPublicApprovalBell,
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
                        const SizedBox(height: 4),
                        Text(
                          '投稿: ${_formatOwnNoteTimestamp(note)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (onApprovalNoticeTap != null &&
                      (note.isPublicApprovalPending ||
                          note.isPublicApprovalRejected))
                    _AnimatedAttentionIconButton(
                      icon: Icons.warning_amber_rounded,
                      color: Colors.amber.shade700,
                      tooltip: '公開申請の状態',
                      animate: note.isPublicApprovalRejected,
                      onPressed: () => onApprovalNoticeTap!(note),
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
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    if (showTeacherHiddenNotice)
                      Text(
                        '先生によって非公開中',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      _noteToggleStatusLabel(note),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
    required this.onOpenRestrictionSettings,
    required this.onResolvePublicApproval,
    required this.isPublicApprovalProcessing,
    required this.suppressPublicApprovalBell,
  });

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;
  final ValueChanged<LessonNote>? onToggleModeration;
  final ValueChanged<LessonNote>? onOpenRestrictionSettings;
  final ValueChanged<LessonNote>? onResolvePublicApproval;
  final bool isPublicApprovalProcessing;
  final bool suppressPublicApprovalBell;

  @override
  Widget build(BuildContext context) {
    PublicUserProfile fallbackProfile() {
      final fallback = fallbackPublicUserProfile(
        userId: note.authorId,
        role: publicUserProfileRoleStudent,
        displayName: note.authorName,
      );
      final avatarColorName = (note.authorAvatarColorName ?? '').trim();
      if (!profileAvatarColors.containsKey(avatarColorName)) {
        return fallback;
      }
      return PublicUserProfile(
        userId: fallback.userId,
        role: fallback.role,
        displayName: fallback.displayName,
        avatarColorName: avatarColorName,
        bio: fallback.bio,
        updatedAt: fallback.updatedAt,
      );
    }

    Widget buildCard(PublicUserProfile profile) {
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
                  onTap: note.authorProfileVisible
                      ? () {
                          showPublicUserProfilePreview(
                            context: context,
                            userId: note.authorId,
                            role: publicUserProfileRoleStudent,
                            fallbackDisplayName: note.authorName,
                            isOwner: false,
                          );
                        }
                      : null,
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
                                  Text(
                                    note.tags.map((tag) => '#$tag').join(' '),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (note.hasCitationEdits &&
                              (note.id ?? '').isNotEmpty)
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onTertiaryContainer,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          if (onResolvePublicApproval != null &&
                              note.isPublicApprovalPending &&
                              !suppressPublicApprovalBell &&
                              !isPublicApprovalProcessing)
                            Positioned(
                              top: 8,
                              right: note.hasCitationEdits ? 56 : 8,
                              child: _AnimatedAttentionIconButton(
                                icon: Icons.notifications_active_outlined,
                                color: Colors.red.shade400,
                                tooltip: '公開申請の確認',
                                animate: true,
                                onPressed: () => onResolvePublicApproval!(note),
                              ),
                            ),
                          if (isPublicApprovalProcessing)
                            Positioned(
                              top: 14,
                              right: note.hasCitationEdits ? 62 : 14,
                              child: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
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
                                ? '先生によって非公開中'
                                : note.isPublicApprovalPending
                                ? '公開申請中'
                                : note.isPublicApprovalRejected
                                ? '公開申請が不許可'
                                : note.isStudentPublic
                                ? '学習者にも公開'
                                : '先生にだけ公開',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: note.isTeacherHidden
                                      ? FontWeight.w600
                                      : null,
                                  color: note.isTeacherHidden
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(
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
                          if (onOpenRestrictionSettings != null)
                            TextButton(
                              onPressed: () => onOpenRestrictionSettings!(note),
                              child: const Text('非公開詳細設定'),
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
    }

    final fallback = fallbackProfile();
    if (!note.authorProfileVisible) {
      return buildCard(fallback);
    }
    return StreamBuilder<PublicUserProfile>(
      stream: publicUserProfileStream(
        userId: note.authorId,
        role: publicUserProfileRoleStudent,
        fallbackDisplayName: note.authorName,
      ),
      builder: (context, snapshot) {
        return buildCard(snapshot.data ?? fallback);
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
  return _formatPostedTimestamp(lessonNotePostedAt(note));
}

String _formatOwnNoteTimestamp(LessonNote note) {
  return _formatPostedTimestamp(lessonNotePostedAt(note));
}

String _formatPostedTimestamp(Timestamp? timestamp) {
  if (timestamp == null) {
    return '投稿日時不明';
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
  final approvalLabel = note.isPublicApprovalPending
      ? ' / 承認:申請中'
      : note.isPublicApprovalRejected
      ? ' / 承認:不許可'
      : '';
  return '公開:$visibilityLabel / 引用:$isCitationOn$approvalLabel';
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
  bool _requestPublicApproval = false;
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
    _requestPublicApproval = note?.isPublicApprovalPending ?? false;
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

  bool get _isPublicLocked =>
      widget.note?.visibility == LessonNoteVisibility.public;

  bool get _isTeacherOnlyLocked =>
      widget.note?.visibility == LessonNoteVisibility.teacherOnly;

  bool get _isCitationLocked => widget.note?.allowsQuestionCitation == true;

  bool get _canChangeVisibility => _canPublish && !_isPublicLocked;

  bool get _wasPendingApproval => widget.note?.isPublicApprovalPending == true;

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
            : _isTeacherOnlyLocked
            ? _visibility == LessonNoteVisibility.public
                  ? LessonNoteVisibility.public
                  : LessonNoteVisibility.teacherOnly
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
        requestPublicApproval: _requestPublicApproval,
        wasPublic: widget.note?.visibility == LessonNoteVisibility.public,
        wasTeacherOnly:
            widget.note?.visibility == LessonNoteVisibility.teacherOnly,
        wasPublicApprovalPending: widget.note?.isPublicApprovalPending == true,
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
              onSelected: _isPublicLocked || _isTeacherOnlyLocked
                  ? null
                  : _toggleAttachment,
            ),
          ],
        ),
        if (!_canPublish) ...[
          const SizedBox(height: 8),
          const Text('音声添付またはコピー元メモは公開できません。'),
        ],
        SwitchListTile(
          title: Row(
            children: [
              const Expanded(child: Text('受講者と先生に公開する')),
              if (_wasPendingApproval)
                Text(
                  '申請中（現時点では未公開）',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          subtitle: Text(
            _wasPendingApproval
                ? '先生の許可待ちです。保存するまで申請中表示は消えません。'
                : _isPublicLocked
                ? '一度公開したメモは後から非公開に戻せません。本文などは編集できます。'
                : _isTeacherOnlyLocked
                ? 'オフにすると先生だけ公開に戻ります。'
                : '公開メモは同じ講座・レッスンのユーザーが閲覧できます。',
          ),
          value:
              (_visibility == LessonNoteVisibility.public ||
                  _isPublicLocked ||
                  (_wasPendingApproval && _requestPublicApproval)) &&
              _canPublish,
          onChanged: !_canChangeVisibility
              ? null
              : (value) {
                  final wasTeacherOnly =
                      _visibility == LessonNoteVisibility.teacherOnly;
                  setState(() {
                    _visibility = value
                        ? LessonNoteVisibility.public
                        : _isTeacherOnlyLocked
                        ? LessonNoteVisibility.teacherOnly
                        : LessonNoteVisibility.private;
                    _requestPublicApproval = value && wasTeacherOnly;
                  });
                  if (value && wasTeacherOnly && !_wasPendingApproval) {
                    unawaited(_showPublicApprovalRequiredDialog());
                  }
                },
        ),
        SwitchListTile(
          title: const Text('先生にだけ公開する'),
          subtitle: Text(
            _isPublicLocked
                ? '一度受講者にも公開したメモは、先生だけ公開に戻せません。'
                : _isTeacherOnlyLocked
                ? '一度先生にだけ公開したメモは、完全非公開に戻せません。'
                : 'オンの場合は先生だけが閲覧できます。',
          ),
          value: _visibility == LessonNoteVisibility.teacherOnly && _canPublish,
          onChanged:
              !_canPublish ||
                  _isPublicLocked ||
                  _isTeacherOnlyLocked ||
                  _visibility == LessonNoteVisibility.public
              ? null
              : (value) {
                  setState(() {
                    _visibility = value
                        ? LessonNoteVisibility.teacherOnly
                        : LessonNoteVisibility.private;
                    _requestPublicApproval = false;
                  });
                },
        ),
        SwitchListTile(
          title: const Text('質問での引用を許可する'),
          subtitle: Text(
            _isCitationLocked
                ? '一度許可した引用は後から取り消せません。'
                : _allowsQuestionCitation
                ? '保存するまでは引用許可を取り消せます。'
                : '許可すると、他の学習者がこの公開メモを引用して質問できます。',
          ),
          value: _allowsQuestionCitation,
          onChanged: !_canPublish || _isCitationLocked
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
        if ((_isPublicLocked || _isTeacherOnlyLocked) &&
            value == lessonNoteAttachmentAudio) {
          return;
        }
        _attachmentTypes.add(value);
        if (value == lessonNoteAttachmentAudio) {
          _visibility = LessonNoteVisibility.private;
          _requestPublicApproval = false;
        }
      } else {
        _attachmentTypes.remove(value);
      }
    });
  }

  Future<void> _showPublicApprovalRequiredDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('先生が受講者に公開することを許可すれば公開されます。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

class _AnimatedAttentionIconButton extends StatefulWidget {
  const _AnimatedAttentionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.animate,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final bool animate;
  final VoidCallback onPressed;

  @override
  State<_AnimatedAttentionIconButton> createState() =>
      _AnimatedAttentionIconButtonState();
}

class _AnimatedAttentionIconButtonState
    extends State<_AnimatedAttentionIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _rotation = Tween<double>(
      begin: -0.22,
      end: 0.22,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedAttentionIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) {
      return;
    }
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      icon: AnimatedBuilder(
        animation: _rotation,
        builder: (context, child) {
          return Transform.rotate(
            angle: widget.animate ? _rotation.value : 0,
            child: child,
          );
        },
        child: Icon(widget.icon, color: widget.color),
      ),
    );
  }
}

enum _PublicApprovalDecision { approve, reject }

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
    required this.requestPublicApproval,
    required this.wasPublic,
    required this.wasTeacherOnly,
    required this.wasPublicApprovalPending,
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
  final bool requestPublicApproval;
  final bool wasPublic;
  final bool wasTeacherOnly;
  final bool wasPublicApprovalPending;
}
