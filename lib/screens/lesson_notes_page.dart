import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/lesson_note.dart';

class LessonNotesPage extends StatefulWidget {
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
  State<LessonNotesPage> createState() => _LessonNotesPageState();
}

class _LessonNotesPageState extends State<LessonNotesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _message;

  String get _courseId =>
      widget.course.id ?? widget.course.title.replaceAll('/', '_');

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
              snapshot.docs.map(LessonNoteFolder.fromFirestore).toList()
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
            snapshot.docs.map(LessonNote.fromFirestore).toList(),
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
        .snapshots()
        .map((snapshot) {
          return sortLessonNotesByUpdatedAt(
            snapshot.docs.map(LessonNote.fromFirestore).toList(),
          );
        });
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダを作成'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'フォルダ名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    controller.dispose();

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

  Future<void> _saveNote(_LessonNoteDraft draft) async {
    if (Firebase.apps.isEmpty) {
      if (mounted) {
        setState(() {
          _message = 'メモ保存にはログインとFirebase設定が必要です。';
        });
      }
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _message = 'メモ保存にはログインが必要です。';
        });
      }
      return;
    }

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
    final savedVisibility = canPublish
        ? visibility
        : lessonNoteVisibilityPrivate;
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
      'updatedAt': now,
      if (draft.noteId == null) 'createdAt': now,
    };

    final batch = firestore.batch()
      ..set(noteRef, data, SetOptions(merge: true));
    final publicRef = firestore.collection('publicLessonNotes').doc(noteId);
    if (savedVisibility == lessonNoteVisibilityPublic) {
      batch.set(publicRef, {
        ...data,
        'noteId': noteId,
        'favoriteCount': 0,
        'ratingAverage': 0,
        'ratingCount': 0,
        'copyCount': 0,
      }, SetOptions(merge: true));
    } else if (draft.wasPublic) {
      batch.delete(publicRef);
    }

    await batch.commit();
    if (mounted) {
      setState(() {
        _message = canPublish || visibility == lessonNoteVisibilityPrivate
            ? 'メモを保存しました。'
            : '音声添付またはコピー元メモは公開できないため、非公開で保存しました。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('レッスンメモ'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '自分のメモ'),
              Tab(text: '公開メモ'),
            ],
          ),
        ),
        body: StreamBuilder<List<LessonNoteFolder>>(
          stream: _foldersStream(),
          builder: (context, folderSnapshot) {
            final folders = folderSnapshot.data ?? const <LessonNoteFolder>[];
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
                        query: _query,
                        emptyText: 'このレッスンのメモはまだありません。',
                        onTap: (note) =>
                            _openEditor(note: note, folders: folders),
                        action: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openEditor(folders: folders),
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
                      _LessonNoteList(
                        notesStream: _publicNotesStream(),
                        query: _query,
                        emptyText: '公開メモはまだありません。',
                        onTap: null,
                        action: const Text('コピー・評価・お気に入りは後で追加します。'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LessonNoteList extends StatelessWidget {
  const _LessonNoteList({
    required this.notesStream,
    required this.query,
    required this.emptyText,
    required this.action,
    required this.onTap,
  });

  final Stream<List<LessonNote>> notesStream;
  final String query;
  final String emptyText;
  final Widget action;
  final ValueChanged<LessonNote>? onTap;

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
            else
              for (final note in notes)
                _LessonNoteCard(note: note, onTap: onTap),
          ],
        );
      },
    );
  }
}

class _LessonNoteCard extends StatelessWidget {
  const _LessonNoteCard({required this.note, required this.onTap});

  final LessonNote note;
  final ValueChanged<LessonNote>? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap == null ? null : () => onTap!(note),
        title: Text(note.title.isEmpty ? '無題のメモ' : note.title),
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

class _LessonNoteEditorPage extends StatefulWidget {
  const _LessonNoteEditorPage({
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.folders,
    required this.onSave,
    this.note,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final List<LessonNoteFolder> folders;
  final LessonNote? note;
  final Future<void> Function(_LessonNoteDraft draft) onSave;

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
    await widget.onSave(
      _LessonNoteDraft(
        noteId: widget.note?.id,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        folderId: selectedFolder?.id ?? '',
        folderName: selectedFolder?.name ?? '',
        visibility: _canPublish ? _visibility : LessonNoteVisibility.private,
        tags: parseLessonNoteTags(_tagsController.text),
        attachmentTypes: _attachmentTypes.toList()..sort(),
        sourceNoteId: widget.note?.sourceNoteId,
        sourceAuthorId: widget.note?.sourceAuthorId,
        isCopied: widget.note?.isCopied ?? false,
        canPublish: widget.note?.canPublish ?? true,
        wasPublic: widget.note?.isPublic ?? false,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.note == null ? 'メモを作成' : 'メモを編集')),
      body: ListView(
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
                onSelected: _toggleAttachment,
              ),
            ],
          ),
          if (!_canPublish) ...[
            const SizedBox(height: 8),
            const Text('音声添付またはコピー元メモは公開できません。'),
          ],
          SwitchListTile(
            title: const Text('受講者と先生に公開する'),
            subtitle: const Text('公開メモは同じ講座・レッスンのユーザーが閲覧できます。'),
            value: _visibility == LessonNoteVisibility.public && _canPublish,
            onChanged: !_canPublish
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
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _toggleAttachment(String value, bool selected) {
    setState(() {
      if (selected) {
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
  final void Function(String value, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (selected) => onSelected(value, selected),
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
