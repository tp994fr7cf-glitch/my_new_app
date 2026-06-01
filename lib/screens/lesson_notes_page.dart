import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/public_user_profile.dart';
import '../services/lesson_interaction_service.dart';
import 'public_user_profile_page.dart';

class LessonNotesPage extends StatelessWidget {
  const LessonNotesPage({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.notesStream,
    this.publicNotesStream,
    this.foldersStream,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonNote>>? notesStream;
  final Stream<List<LessonNote>>? publicNotesStream;
  final Stream<List<LessonNoteFolder>>? foldersStream;

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
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonNote>>? notesStream;
  final Stream<List<LessonNote>>? publicNotesStream;
  final Stream<List<LessonNoteFolder>>? foldersStream;
  final bool isEmbedded;
  final bool isTeacherPreview;

  @override
  State<LessonNotesPanel> createState() => _LessonNotesPanelState();
}

class _LessonNotesPanelState extends State<LessonNotesPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _message;
  LessonNote? _editingNote;
  List<LessonNoteFolder> _editingFolders = const [];
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

    await Navigator.of(context).push(
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
      final visibility = draft.visibility == LessonNoteVisibility.public
          ? lessonNoteVisibilityPublic
          : lessonNoteVisibilityPrivate;
      final now = FieldValue.serverTimestamp();
      final authorName = user.displayName ?? user.email ?? '学習者';
      final canPublish = canPublishLessonNote(
        hasAudioAttachment: draft.attachmentTypes.contains(
          lessonNoteAttachmentAudio,
        ),
        isCopied: draft.isCopied,
        canPublish: draft.canPublish,
      );
      final platformEnabled = await _isNotePublicPlatformEnabled();
      final isPublicLocked = draft.wasPublic && canPublish;
      final savedVisibility = isPublicLocked
          ? lessonNoteVisibilityPublic
          : canPublish && platformEnabled
          ? visibility
          : lessonNoteVisibilityPrivate;
      final publicRef = firestore.collection('publicLessonNotes').doc(noteId);
      final publicSnapshot = draft.wasPublic ? await publicRef.get() : null;
      final publicData = publicSnapshot?.data();
      final hasPublicMirror = publicSnapshot?.exists ?? false;
      final nextHasPublicMirror =
          savedVisibility == lessonNoteVisibilityPublic || hasPublicMirror;
      final publicModerationStatus =
          publicData?['moderationStatus'] as String? ??
          lessonNoteModerationVisible;
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
        'hasPublicMirror': nextHasPublicMirror,
        'isDeleted': false,
        'moderationStatus': lessonNoteModerationVisible,
        'updatedAt': now,
        if (draft.noteId == null) 'createdAt': now,
      };

      final batch = firestore.batch()
        ..set(noteRef, data, SetOptions(merge: true));
      if (savedVisibility == lessonNoteVisibilityPublic ||
          (hasPublicMirror && canPublish)) {
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

      await batch.commit();
      _showMessage(
        isPublicLocked ||
                canPublish && platformEnabled ||
                visibility == lessonNoteVisibilityPrivate
            ? 'メモを保存しました。'
            : platformEnabled
            ? '音声添付またはコピー元メモは公開できないため、非公開で保存しました。'
            : '先生により公開メモ機能が非公開化されているため、非公開で保存しました。',
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
                        });
                      },
                      onSaved: () {
                        setState(() {
                          _editingNote = null;
                          _isEditingNote = false;
                        });
                      },
                    );
                  },
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
                                onTap: (note) =>
                                    _openEditor(note: note, folders: folders),
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
          notesStream: enabled ? _publicNotesStream() : Stream.value(const []),
          query: _query,
          emptyText: enabled ? '公開メモはまだありません。' : '公開メモ欄は非公開化されています。',
          onTap: (note) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PublicLessonNoteDetailPage(note: note),
              ),
            );
          },
          showAuthor: true,
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

class _LessonNoteList extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonNote>>(
      stream: notesStream,
      builder: (context, snapshot) {
        final notes = (snapshot.data ?? const <LessonNote>[])
            .where((note) => lessonNoteMatchesQuery(note, query))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            action,
            const SizedBox(height: 16),
            if (notes.isEmpty)
              Text(emptyText)
            else if (folders.isEmpty)
              for (final note in notes)
                _LessonNoteCard(
                  note: note,
                  onTap: onTap,
                  showAuthor: showAuthor,
                  onDelete: onDeleteNote,
                )
            else
              ..._buildFolderSections(notes),
          ],
        );
      },
    );
  }

  List<Widget> _buildFolderSections(List<LessonNote> notes) {
    final widgets = <Widget>[];
    final notesByFolder = <String, List<LessonNote>>{};
    for (final note in notes) {
      notesByFolder.putIfAbsent(note.folderId, () => []).add(note);
    }

    for (final folder in folders) {
      final folderNotes = notesByFolder.remove(folder.id ?? '') ?? const [];
      widgets.add(
        _LessonNoteFolderTile(
          folder: folder,
          notes: folderNotes,
          onTapNote: onTap,
          onDeleteNote: onDeleteNote,
          onDeleteFolder: onDeleteFolder,
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }

    final unfiledNotes = notesByFolder.remove('') ?? const [];
    if (unfiledNotes.isNotEmpty) {
      widgets.add(
        _LessonNoteUnfiledSection(
          notes: unfiledNotes,
          onTapNote: onTap,
          onDeleteNote: onDeleteNote,
        ),
      );
    }
    for (final folderNotes in notesByFolder.values) {
      for (final note in folderNotes) {
        widgets.add(
          _LessonNoteCard(
            note: note,
            onTap: onTap,
            showAuthor: showAuthor,
            onDelete: onDeleteNote,
          ),
        );
      }
    }
    return widgets;
  }
}

class _LessonNoteFolderTile extends StatelessWidget {
  const _LessonNoteFolderTile({
    required this.folder,
    required this.notes,
    required this.onTapNote,
    required this.onDeleteNote,
    required this.onDeleteFolder,
  });

  final LessonNoteFolder folder;
  final List<LessonNote> notes;
  final ValueChanged<LessonNote>? onTapNote;
  final ValueChanged<LessonNote>? onDeleteNote;
  final ValueChanged<LessonNoteFolder>? onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
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
            for (final note in notes)
              _LessonNoteCard(
                note: note,
                onTap: onTapNote,
                onDelete: onDeleteNote,
              ),
        ],
      ),
    );
  }
}

class _LessonNoteUnfiledSection extends StatelessWidget {
  const _LessonNoteUnfiledSection({
    required this.notes,
    required this.onTapNote,
    required this.onDeleteNote,
  });

  final List<LessonNote> notes;
  final ValueChanged<LessonNote>? onTapNote;
  final ValueChanged<LessonNote>? onDeleteNote;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.note_outlined),
        title: const Text('フォルダなし'),
        subtitle: Text('${notes.length}件のメモ'),
        children: [
          for (final note in notes)
            _LessonNoteCard(
              note: note,
              onTap: onTapNote,
              onDelete: onDeleteNote,
            ),
        ],
      ),
    );
  }
}

class _LessonNoteCard extends StatelessWidget {
  const _LessonNoteCard({
    required this.note,
    required this.onTap,
    this.showAuthor = false,
    this.onDelete,
  });

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;
  final bool showAuthor;
  final ValueChanged<LessonNote>? onDelete;

  @override
  Widget build(BuildContext context) {
    if (showAuthor) {
      return _PublicLessonNoteCard(note: note, onTap: onTap);
    }
    return Card(
      child: ListTile(
        onTap: onTap == null ? null : () => onTap!(note),
        title: Text(note.title.isEmpty ? '無題のメモ' : note.title),
        trailing: onDelete == null
            ? null
            : IconButton(
                onPressed: () => onDelete!(note),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'メモを削除',
              ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.body.isEmpty ? '本文なし' : note.body),
            if (note.folderName.isNotEmpty) Text('フォルダ: ${note.folderName}'),
            if (note.tags.isNotEmpty)
              Text(note.tags.map((tag) => '#$tag').join(' ')),
            if (note.attachmentTypes.isNotEmpty)
              Text('添付予定: ${note.attachmentTypes.join(', ')}'),
            Text(note.isPublic ? '公開中' : '非公開'),
          ],
        ),
      ),
    );
  }
}

class _PublicLessonNoteCard extends StatelessWidget {
  const _PublicLessonNoteCard({required this.note, required this.onTap});

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;

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
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '学習者にも公開',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
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
      },
    );
  }
}

class _PublicLessonNoteDetailPage extends StatelessWidget {
  const _PublicLessonNoteDetailPage({required this.note});

  final LessonNote note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公開メモ')),
      body: SafeArea(
        child: StreamBuilder<PublicUserProfile>(
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
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PublicProfileAvatar(profile: profile),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
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
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  note.title.isEmpty ? '無題のメモ' : note.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(note.body.isEmpty ? '本文なし' : note.body),
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(note.tags.map((tag) => '#$tag').join(' ')),
                ],
                if (note.attachmentTypes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('添付予定: ${note.attachmentTypes.join(', ')}'),
                ],
              ],
            );
          },
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

  bool get _isPublicLocked => widget.note?.hasPublicMirror == true;

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
        wasPublic: widget.note?.hasPublicMirror ?? false,
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
  final bool wasPublic;
}
