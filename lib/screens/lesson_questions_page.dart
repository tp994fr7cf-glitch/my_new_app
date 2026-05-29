import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/comment_identity.dart';
import '../models/course.dart';
import '../models/lesson_note.dart';
import '../models/lesson_question.dart';
import '../services/lesson_interaction_service.dart';
import '../utils/firestore_parsing.dart';

class LessonQuestionsPanel extends StatefulWidget {
  const LessonQuestionsPanel({
    super.key,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    this.questionsStream,
    this.publicQuestionsStream,
    this.isEmbedded = false,
  });

  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final Stream<List<LessonQuestion>>? questionsStream;
  final Stream<List<LessonQuestion>>? publicQuestionsStream;
  final bool isEmbedded;

  @override
  State<LessonQuestionsPanel> createState() => _LessonQuestionsPanelState();
}

class _LessonQuestionsPanelState extends State<LessonQuestionsPanel> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';
  String? _message;
  LessonQuestion? _editingQuestion;
  LessonQuestion? _selectedQuestion;
  final LessonInteractionService _lessonInteractionService =
      const LessonInteractionService();

  String get _courseId => widget.course.storageId;

  String? get _currentUserId =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;

  bool get _isCurrentUserTeacher =>
      _currentUserId != null && widget.course.instructorId == _currentUserId;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Stream<List<LessonQuestion>> _questionsStream() {
    final provided = widget.questionsStream;
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
        .collection('lessonQuestions')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .snapshots()
        .map((snapshot) {
          return sortLessonQuestionsByUpdatedAt(
            snapshot.docs
                .map(LessonQuestion.fromFirestore)
                .where((question) => !question.isDeleted)
                .toList(),
          );
        });
  }

  Stream<List<LessonQuestion>> _publicQuestionsStream() {
    final provided = widget.publicQuestionsStream;
    if (provided != null) {
      return provided;
    }
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return FirebaseFirestore.instance
        .collection('publicLessonQuestions')
        .where('courseId', isEqualTo: _courseId)
        .where('lessonNumber', isEqualTo: widget.lessonNumber)
        .snapshots()
        .map((snapshot) {
          return sortLessonQuestionsByUpdatedAt(
            snapshot.docs
                .map(LessonQuestion.fromFirestore)
                .where(
                  (question) =>
                      !question.isDeleted && !question.isTeacherHidden,
                )
                .toList(),
          );
        });
  }

  Stream<bool> _questionPublicPlatformEnabledStream() {
    return _lessonInteractionService.publicFeatureEnabledStream(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonQuestionsPublicEnabledField,
    );
  }

  Stream<List<LessonNote>> _quotableNotesStream() {
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
            snapshot.docs
                .map(LessonNote.fromFirestore)
                .where((note) => note.isPubliclyVisible)
                .toList(),
          );
        });
  }

  Future<bool> _isQuestionPublicPlatformEnabled() async {
    return _lessonInteractionService.isPublicFeatureEnabled(
      courseId: _courseId,
      lessonNumber: widget.lessonNumber,
      fieldName: LessonInteractionService.lessonQuestionsPublicEnabledField,
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

  Future<bool> _saveQuestion(_LessonQuestionDraft draft) async {
    if (Firebase.apps.isEmpty) {
      _showMessage('質問保存にはログインとFirebase設定が必要です。');
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('質問保存にはログインが必要です。');
      return false;
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final questionRef = draft.questionId == null
          ? firestore
                .collection('users')
                .doc(user.uid)
                .collection('lessonQuestions')
                .doc()
          : firestore
                .collection('users')
                .doc(user.uid)
                .collection('lessonQuestions')
                .doc(draft.questionId);
      final questionId = questionRef.id;
      final platformEnabled = await _isQuestionPublicPlatformEnabled();
      final requestedPublic =
          draft.target == LessonQuestionTarget.everyone ||
          draft.visibility == LessonQuestionVisibility.public;
      final visibility = requestedPublic && platformEnabled
          ? lessonQuestionVisibilityPublic
          : lessonQuestionVisibilityTeacherOnly;
      final now = FieldValue.serverTimestamp();
      final data = {
        'userId': user.uid,
        'authorId': user.uid,
        'authorName': user.displayName ?? user.email ?? '学習者',
        'authorDisplayName': _isCurrentUserTeacher ? '先生' : null,
        'courseId': _courseId,
        'courseTitle': widget.course.title,
        'lessonNumber': widget.lessonNumber,
        'lessonTitle': widget.lesson.title,
        'title': '',
        'body': draft.body,
        'visibility': visibility,
        'target': draft.target == LessonQuestionTarget.everyone
            ? lessonQuestionTargetEveryone
            : lessonQuestionTargetTeacher,
        'attachmentTypes': draft.attachmentTypes,
        'quotedNoteId': draft.quotedNoteId,
        'quotedNoteTitle': draft.quotedNoteTitle,
        'quotedNoteBody': draft.quotedNoteBody,
        'status': lessonQuestionStatusOpen,
        'isDeleted': false,
        'moderationStatus': lessonNoteModerationVisible,
        'updatedAt': now,
        if (draft.questionId == null) ...{
          'answerCount': 0,
          'createdAt': now,
        },
      };
      final batch = firestore.batch()
        ..set(questionRef, data, SetOptions(merge: true));
      final publicRef = firestore
          .collection('publicLessonQuestions')
          .doc(questionId);
      if (visibility == lessonQuestionVisibilityPublic) {
        final publicSnapshot = await publicRef.get();
        final publicModerationStatus =
            publicSnapshot.data()?['moderationStatus'] as String? ??
            lessonNoteModerationVisible;
        batch.set(publicRef, {
          ...data,
          'questionId': questionId,
          'moderationStatus': publicModerationStatus,
        }, SetOptions(merge: true));
      } else if (draft.wasPublic) {
        batch.delete(publicRef);
      }
      await batch.commit();
      if (mounted) {
        setState(() {
          _editingQuestion = null;
        });
      }
      _showMessage(
        visibility == lessonQuestionVisibilityPublic || platformEnabled
            ? '質問コメントを投稿しました。'
            : '先生により公開質問欄が非公開化されているため、先生にだけ公開で保存しました。',
      );
      return true;
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? '質問コメントの投稿に失敗しました。');
      return false;
    } catch (error) {
      _showMessage('質問コメントの投稿に失敗しました: $error');
      return false;
    }
  }

  Future<void> _deleteQuestion(LessonQuestion question) async {
    if (Firebase.apps.isEmpty || question.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch()
      ..set(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestions')
            .doc(question.id),
        {
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      )
      ..delete(firestore.collection('publicLessonQuestions').doc(question.id));
    await batch.commit();
  }

  Stream<List<LessonQuestionAnswer>> _answersStream(LessonQuestion question) {
    if (Firebase.apps.isEmpty || question.id == null) {
      return Stream.value(const []);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const []);
    }
    final query = question.isPublic
        ? FirebaseFirestore.instance
              .collection('publicLessonQuestionAnswers')
              .where('questionId', isEqualTo: question.id)
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lessonQuestionAnswers')
              .where('questionId', isEqualTo: question.id);
    return query.snapshots().map((snapshot) {
      final answers = snapshot.docs
          .map(LessonQuestionAnswer.fromFirestore)
          .where((answer) => !answer.isDeleted)
          .toList();
      answers.sort((a, b) {
        return timestampOrEpoch(a.createdAt).compareTo(
          timestampOrEpoch(b.createdAt),
        );
      });
      return answers;
    });
  }

  Future<void> _saveAnswer(
    LessonQuestion question,
    _LessonQuestionAnswerDraft draft,
  ) async {
    if (Firebase.apps.isEmpty ||
        question.id == null ||
        draft.body.trim().isEmpty) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final answerRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('lessonQuestionAnswers')
        .doc();
    final now = FieldValue.serverTimestamp();
    final data = {
      'questionId': question.id,
      'courseId': _courseId,
      'courseTitle': widget.course.title,
      'lessonNumber': widget.lessonNumber,
      'lessonTitle': widget.lesson.title,
      'authorId': user.uid,
      'authorName': user.displayName ?? user.email ?? '学習者',
      'authorDisplayName': _isCurrentUserTeacher ? '先生' : null,
      'authorRole': _isCurrentUserTeacher ? 'teacher' : 'student',
      'body': draft.body.trim(),
      'attachmentTypes': <String>[],
      'parentCommentId': draft.parentCommentId,
      'parentCommentType': draft.parentCommentType,
      'replyToAuthorId': draft.replyToAuthorId,
      'replyToDisplayName': draft.replyToDisplayName,
      'replyToBodyPreview': draft.replyToBodyPreview,
      'quotedNoteId': draft.quotedNoteId,
      'quotedNoteTitle': draft.quotedNoteTitle,
      'quotedNoteBody': draft.quotedNoteBody,
      'isDeleted': false,
      'moderationStatus': lessonNoteModerationVisible,
      'createdAt': now,
      'updatedAt': now,
    };
    final batch = firestore.batch()..set(answerRef, data);
    if (question.isPublic) {
      batch.set(
        firestore.collection('publicLessonQuestionAnswers').doc(answerRef.id),
        {...data, 'answerId': answerRef.id},
      );
    }
    await batch.commit();
  }

  Future<void> _deleteAnswer(
    LessonQuestion question,
    LessonQuestionAnswer answer,
  ) async {
    if (Firebase.apps.isEmpty || answer.id == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != answer.authorId) {
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final deletedData = {
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = firestore.batch()
      ..set(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('lessonQuestionAnswers')
            .doc(answer.id),
        deletedData,
        SetOptions(merge: true),
      );
    if (question.isPublic) {
      batch.set(
        firestore.collection('publicLessonQuestionAnswers').doc(answer.id),
        deletedData,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final content = DefaultTabController(
      length: 2,
      child: Card(
        margin: widget.isEmbedded ? EdgeInsets.zero : null,
        child: Padding(
          padding: widget.isEmbedded
              ? const EdgeInsets.only(top: 12)
              : EdgeInsets.zero,
          child: _buildContent(),
        ),
      ),
    );
    return widget.isEmbedded ? SizedBox(height: 560, child: content) : content;
  }

  Widget _buildContent() {
    final selectedQuestion = _selectedQuestion;
    if (selectedQuestion != null) {
      return _LessonQuestionDetail(
        question: selectedQuestion,
        answersStream: _answersStream(selectedQuestion),
        quotableNotesStream: _quotableNotesStream(),
        currentUserId: _currentUserId,
        isCurrentUserTeacher: _isCurrentUserTeacher,
        onBack: () => setState(() => _selectedQuestion = null),
        onSaveAnswer: (draft) => _saveAnswer(selectedQuestion, draft),
        onDeleteQuestion: () async {
          await _deleteQuestion(selectedQuestion);
          if (mounted) {
            setState(() => _selectedQuestion = null);
          }
        },
        onDeleteAnswer: (answer) => _deleteAnswer(selectedQuestion, answer),
      );
    }
    final editingQuestion = _editingQuestion;
    if (editingQuestion != null) {
      return _LessonQuestionEditor(
        question: editingQuestion,
        course: widget.course,
        lesson: widget.lesson,
        lessonNumber: widget.lessonNumber,
        onCancel: () => setState(() => _editingQuestion = null),
        onSave: _saveQuestion,
        quotableNotesStream: _quotableNotesStream(),
      );
    }
    return _buildQuestionList();
  }

  Widget _buildQuestionList() {
    return Column(
      children: [
        if (widget.isEmbedded) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.question_answer_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('質問コメント', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const TabBar(
          tabs: [
            Tab(text: '自分の質問'),
            Tab(text: '公開質問'),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '質問を検索',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
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
                    _QuestionList(
                      questionsStream: _questionsStream(),
                      query: _query,
                      currentUserId: _currentUserId,
                      isCurrentUserTeacher: _isCurrentUserTeacher,
                      action: FilledButton.icon(
                        onPressed: () => setState(
                          () => _editingQuestion = const LessonQuestion(
                            authorId: '',
                            authorName: '',
                            courseId: '',
                            courseTitle: '',
                            lessonNumber: 1,
                            lessonTitle: '',
                            title: '',
                            body: '',
                            visibility: LessonQuestionVisibility.teacherOnly,
                            target: LessonQuestionTarget.teacher,
                            attachmentTypes: [],
                          ),
                        ),
                        icon: const Icon(Icons.add_comment),
                        label: const Text('質問を作成'),
                      ),
                      emptyText: 'このレッスンの質問はまだありません。',
                      onTap: (question) =>
                          setState(() => _selectedQuestion = question),
                      onDelete: _deleteQuestion,
                      onEdit: (question) =>
                          setState(() => _editingQuestion = question),
                    ),
                    StreamBuilder<bool>(
                      stream: _questionPublicPlatformEnabledStream(),
                      builder: (context, platformSnapshot) {
                        final enabled = platformSnapshot.data ?? true;
                        if (!enabled) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('先生により、このレッスンの公開質問欄は非公開化されています。'),
                          );
                        }
                        return _QuestionList(
                          questionsStream: _publicQuestionsStream(),
                          query: _query,
                          currentUserId: _currentUserId,
                          isCurrentUserTeacher: _isCurrentUserTeacher,
                          action: const Text('回答コメント作成は初期版として後で拡張します。'),
                          emptyText: '公開質問はまだありません。',
                          onTap: (question) =>
                              setState(() => _selectedQuestion = question),
                          onDelete: null,
                          onEdit: null,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionList extends StatelessWidget {
  const _QuestionList({
    required this.questionsStream,
    required this.query,
    required this.action,
    required this.emptyText,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
  });

  final Stream<List<LessonQuestion>> questionsStream;
  final String query;
  final Widget action;
  final String emptyText;
  final ValueChanged<LessonQuestion>? onTap;
  final ValueChanged<LessonQuestion>? onDelete;
  final ValueChanged<LessonQuestion>? onEdit;
  final String? currentUserId;
  final bool isCurrentUserTeacher;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LessonQuestion>>(
      stream: questionsStream,
      builder: (context, snapshot) {
        final questions = (snapshot.data ?? const <LessonQuestion>[])
            .where((question) => lessonQuestionMatchesQuery(question, query))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            action,
            const SizedBox(height: 16),
            if (questions.isEmpty)
              Text(emptyText)
            else
              for (final question in questions)
                _CommentBubble(
                  body: question.body,
                  authorId: question.authorId,
                  authorName: question.authorName,
                  authorDisplayName: question.authorDisplayName,
                  authorRole: 'student',
                  attachmentTypes: question.attachmentTypes,
                  quotedNoteTitle: question.quotedNoteTitle,
                  quotedNoteBody: question.quotedNoteBody,
                  isOwner: currentUserId == question.authorId,
                  isTeacher: isCurrentUserTeacher,
                  onTap: onTap == null ? null : () => onTap!(question),
                  onReply: onTap == null ? null : () => onTap!(question),
                  onEdit: onEdit == null ? null : () => onEdit!(question),
                  onDelete: onDelete == null ? null : () => onDelete!(question),
                ),
          ],
        );
      },
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.attachmentTypes,
    required this.isOwner,
    required this.isTeacher,
    this.authorDisplayName,
    this.quotedNoteTitle,
    this.quotedNoteBody,
    this.replyToDisplayName,
    this.replyToBodyPreview,
    this.onTap,
    this.onReply,
    this.onEdit,
    this.onDelete,
  });

  final String body;
  final String authorId;
  final String authorName;
  final String? authorDisplayName;
  final String authorRole;
  final List<String> attachmentTypes;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
  final String? replyToDisplayName;
  final String? replyToBodyPreview;
  final bool isOwner;
  final bool isTeacher;
  final VoidCallback? onTap;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final identity = commentIdentityFor(
      authorId: authorId,
      authorName: authorName,
      authorDisplayName: authorDisplayName,
      authorRole: authorRole,
    );
    final canOperate = isOwner || isTeacher || onReply != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: identity.color,
            child: Text(
              identity.displayName,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 18, right: 32),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
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
                          if (replyToDisplayName != null) ...[
                            _ReplyLine(
                              displayName: replyToDisplayName!,
                              bodyPreview: replyToBodyPreview ?? '',
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(body.isEmpty ? '本文なし' : body),
                          if (attachmentTypes.isNotEmpty ||
                              (quotedNoteTitle ?? '').isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final type in attachmentTypes)
                                  _AttachmentPreviewChip(
                                    label: type == lessonNoteAttachmentPdf
                                        ? 'PDF'
                                        : '画像',
                                    detail: 'アップロード機能追加後に表示します。',
                                  ),
                                if ((quotedNoteTitle ?? '').isNotEmpty)
                                  _AttachmentPreviewChip(
                                    label: 'レッスンメモ',
                                    detail:
                                        '${quotedNoteTitle ?? '無題のメモ'}\n${quotedNoteBody ?? ''}',
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Text(
                    identity.displayName,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                if (canOperate)
                  Positioned(
                    right: 0,
                    top: 10,
                    child: PopupMenuButton<_CommentAction>(
                      tooltip: 'コメント操作',
                      onSelected: (action) {
                        switch (action) {
                          case _CommentAction.reply:
                            onReply?.call();
                          case _CommentAction.edit:
                            onEdit?.call();
                          case _CommentAction.delete:
                            onDelete?.call();
                        }
                      },
                      itemBuilder: (context) => [
                        if (onReply != null)
                          const PopupMenuItem(
                            value: _CommentAction.reply,
                            child: Text('返信'),
                          ),
                        if (isOwner && onEdit != null)
                          const PopupMenuItem(
                            value: _CommentAction.edit,
                            child: Text('編集'),
                          ),
                        if ((isOwner || isTeacher) && onDelete != null)
                          const PopupMenuItem(
                            value: _CommentAction.delete,
                            child: Text('削除'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CommentAction { reply, edit, delete }

class _ReplyLine extends StatelessWidget {
  const _ReplyLine({required this.displayName, required this.bodyPreview});

  final String displayName;
  final String bodyPreview;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 2,
          height: 36,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$displayName への返信\n$bodyPreview',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ReplyTargetPreview extends StatelessWidget {
  const _ReplyTargetPreview({
    required this.displayName,
    required this.bodyPreview,
    required this.onClear,
  });

  final String displayName;
  final String bodyPreview;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        title: Text('$displayName に返信'),
        subtitle: Text(bodyPreview),
        trailing: IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close),
          tooltip: '返信先を解除',
        ),
      ),
    );
  }
}

class _AttachmentPreviewChip extends StatelessWidget {
  const _AttachmentPreviewChip({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.insert_drive_file, size: 18),
      label: Text(label),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                _AttachmentPreviewPage(title: label, detail: detail),
          ),
        );
      },
    );
  }
}

class _AttachmentPreviewPage extends StatelessWidget {
  const _AttachmentPreviewPage({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(detail.isEmpty ? '表示できるデータはまだありません。' : detail),
      ),
    );
  }
}

String _displayNameForQuestion(LessonQuestion question) {
  return commentIdentityFor(
    authorId: question.authorId,
    authorName: question.authorName,
    authorDisplayName: question.authorDisplayName,
    authorRole: 'student',
  ).displayName;
}

String _displayNameForAnswer(LessonQuestionAnswer answer) {
  return commentIdentityFor(
    authorId: answer.authorId,
    authorName: answer.authorName,
    authorDisplayName: answer.authorDisplayName,
    authorRole: answer.authorRole,
  ).displayName;
}

String _previewText(String value) {
  final normalized = value.replaceAll('\n', ' ').trim();
  if (normalized.length <= 36) {
    return normalized;
  }
  return '${normalized.substring(0, 36)}...';
}

class _LessonQuestionDetail extends StatefulWidget {
  const _LessonQuestionDetail({
    required this.question,
    required this.answersStream,
    required this.quotableNotesStream,
    required this.currentUserId,
    required this.isCurrentUserTeacher,
    required this.onBack,
    required this.onSaveAnswer,
    required this.onDeleteQuestion,
    required this.onDeleteAnswer,
  });

  final LessonQuestion question;
  final Stream<List<LessonQuestionAnswer>> answersStream;
  final Stream<List<LessonNote>> quotableNotesStream;
  final String? currentUserId;
  final bool isCurrentUserTeacher;
  final VoidCallback onBack;
  final Future<void> Function(_LessonQuestionAnswerDraft draft) onSaveAnswer;
  final Future<void> Function() onDeleteQuestion;
  final Future<void> Function(LessonQuestionAnswer answer) onDeleteAnswer;

  @override
  State<_LessonQuestionDetail> createState() => _LessonQuestionDetailState();
}

class _LessonQuestionDetailState extends State<_LessonQuestionDetail> {
  final TextEditingController _answerController = TextEditingController();
  String _quotedNoteId = '';
  String _quotedNoteTitle = '';
  String _quotedNoteBody = '';
  String? _replyParentId;
  String _replyParentType = 'question';
  String? _replyToAuthorId;
  String? _replyToDisplayName;
  String? _replyToBodyPreview;
  bool _isSaving = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _saveAnswer() async {
    setState(() => _isSaving = true);
    await widget.onSaveAnswer(
      _LessonQuestionAnswerDraft(
        body: _answerController.text,
        parentCommentId: _replyParentId ?? widget.question.id,
        parentCommentType: _replyParentType,
        replyToAuthorId: _replyToAuthorId ?? widget.question.authorId,
        replyToDisplayName:
            _replyToDisplayName ?? _displayNameForQuestion(widget.question),
        replyToBodyPreview:
            _replyToBodyPreview ?? _previewText(widget.question.body),
        quotedNoteId: _quotedNoteId.isEmpty ? null : _quotedNoteId,
        quotedNoteTitle: _quotedNoteTitle.isEmpty ? null : _quotedNoteTitle,
        quotedNoteBody: _quotedNoteBody.isEmpty ? null : _quotedNoteBody,
      ),
    );
    if (!mounted) {
      return;
    }
    _answerController.clear();
    _clearReplyTarget();
    setState(() => _isSaving = false);
  }

  void _setQuestionReplyTarget() {
    setState(() {
      _replyParentId = widget.question.id;
      _replyParentType = 'question';
      _replyToAuthorId = widget.question.authorId;
      _replyToDisplayName = _displayNameForQuestion(widget.question);
      _replyToBodyPreview = _previewText(widget.question.body);
    });
  }

  void _setAnswerReplyTarget(LessonQuestionAnswer answer) {
    setState(() {
      _replyParentId = answer.id;
      _replyParentType = 'answer';
      _replyToAuthorId = answer.authorId;
      _replyToDisplayName = _displayNameForAnswer(answer);
      _replyToBodyPreview = _previewText(answer.body);
    });
  }

  void _clearReplyTarget() {
    _replyParentId = null;
    _replyParentType = 'question';
    _replyToAuthorId = null;
    _replyToDisplayName = null;
    _replyToBodyPreview = null;
    _quotedNoteId = '';
    _quotedNoteTitle = '';
    _quotedNoteBody = '';
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: '質問一覧に戻る',
              ),
              Text('質問詳細', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CommentBubble(
                body: question.body,
                authorId: question.authorId,
                authorName: question.authorName,
                authorDisplayName: question.authorDisplayName,
                authorRole: 'student',
                attachmentTypes: question.attachmentTypes,
                quotedNoteTitle: question.quotedNoteTitle,
                quotedNoteBody: question.quotedNoteBody,
                isOwner: widget.currentUserId == question.authorId,
                isTeacher: widget.isCurrentUserTeacher,
                onReply: _setQuestionReplyTarget,
                onDelete: widget.currentUserId == question.authorId
                    ? widget.onDeleteQuestion
                    : null,
              ),
              const Divider(height: 32),
              const Text(
                '回答コメント',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<LessonQuestionAnswer>>(
                stream: widget.answersStream,
                builder: (context, snapshot) {
                  final answers =
                      snapshot.data ?? const <LessonQuestionAnswer>[];
                  if (answers.isEmpty) {
                    return const Text('回答コメントはまだありません。');
                  }
                  return Column(
                    children: [
                      for (final answer in answers)
                        _CommentBubble(
                          body: answer.body,
                          authorId: answer.authorId,
                          authorName: answer.authorName,
                          authorDisplayName: answer.authorDisplayName,
                          authorRole: answer.authorRole,
                          attachmentTypes: answer.attachmentTypes,
                          quotedNoteTitle: answer.quotedNoteTitle,
                          quotedNoteBody: answer.quotedNoteBody,
                          replyToDisplayName: answer.replyToDisplayName,
                          replyToBodyPreview: answer.replyToBodyPreview,
                          isOwner: widget.currentUserId == answer.authorId,
                          isTeacher: widget.isCurrentUserTeacher,
                          onReply: () => _setAnswerReplyTarget(answer),
                          onDelete: widget.currentUserId == answer.authorId
                              ? () => widget.onDeleteAnswer(answer)
                              : null,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_replyToDisplayName != null) ...[
                _ReplyTargetPreview(
                  displayName: _replyToDisplayName!,
                  bodyPreview: _replyToBodyPreview ?? '',
                  onClear: () => setState(_clearReplyTarget),
                ),
                const SizedBox(height: 8),
              ],
              StreamBuilder<List<LessonNote>>(
                stream: widget.quotableNotesStream,
                builder: (context, snapshot) {
                  final notes = snapshot.data ?? const <LessonNote>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _quotedNoteId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '引用する公開メモ',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('引用なし')),
                      for (final note in notes)
                        DropdownMenuItem(
                          value: note.id ?? '',
                          child: Text(
                            note.title.isEmpty ? '無題のメモ' : note.title,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      LessonNote? selectedNote;
                      for (final note in notes) {
                        if (note.id == value) {
                          selectedNote = note;
                          break;
                        }
                      }
                      setState(() {
                        _quotedNoteId = value ?? '';
                        _quotedNoteTitle = selectedNote?.title ?? '';
                        _quotedNoteBody = selectedNote?.body ?? '';
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _answerController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '回答コメントを書く',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveAnswer,
                icon: const Icon(Icons.reply),
                label: const Text('回答を投稿'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LessonQuestionEditor extends StatefulWidget {
  const _LessonQuestionEditor({
    required this.question,
    required this.course,
    required this.lesson,
    required this.lessonNumber,
    required this.onCancel,
    required this.onSave,
    required this.quotableNotesStream,
  });

  final LessonQuestion? question;
  final Course course;
  final CourseLesson lesson;
  final int lessonNumber;
  final VoidCallback onCancel;
  final Future<bool> Function(_LessonQuestionDraft draft) onSave;
  final Stream<List<LessonNote>> quotableNotesStream;

  @override
  State<_LessonQuestionEditor> createState() => _LessonQuestionEditorState();
}

class _LessonQuestionEditorState extends State<_LessonQuestionEditor> {
  late final TextEditingController _bodyController;
  LessonQuestionVisibility _visibility = LessonQuestionVisibility.teacherOnly;
  LessonQuestionTarget _target = LessonQuestionTarget.teacher;
  String _quotedNoteId = '';
  String _quotedNoteTitle = '';
  String _quotedNoteBody = '';
  final Set<String> _attachmentTypes = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    _bodyController = TextEditingController(text: question?.body ?? '');
    _visibility = question?.visibility ?? LessonQuestionVisibility.teacherOnly;
    _target = question?.target ?? LessonQuestionTarget.teacher;
    _quotedNoteId = question?.quotedNoteId ?? '';
    _quotedNoteTitle = question?.quotedNoteTitle ?? '';
    _quotedNoteBody = question?.quotedNoteBody ?? '';
    _attachmentTypes.addAll(question?.attachmentTypes ?? const []);
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final saved = await widget.onSave(
      _LessonQuestionDraft(
        questionId: widget.question?.id,
        body: _bodyController.text.trim(),
        visibility: _visibility,
        target: _target,
        attachmentTypes: _attachmentTypes.toList()..sort(),
        quotedNoteId: _quotedNoteId.isEmpty ? null : _quotedNoteId,
        quotedNoteTitle: _quotedNoteTitle.isEmpty ? null : _quotedNoteTitle,
        quotedNoteBody: _quotedNoteBody.isEmpty ? null : _quotedNoteBody,
        wasPublic: widget.question?.isPublic ?? false,
      ),
    );
    if (mounted) {
      setState(() => _isSaving = false);
    }
    if (!saved) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.arrow_back),
                tooltip: '質問一覧に戻る',
              ),
              Text(
                widget.question?.id == null ? '質問を作成' : '質問を編集',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.course.title} / レッスン${widget.lessonNumber}: ${widget.lesson.title}',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bodyController,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '質問本文',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<LessonQuestionTarget>(
                segments: const [
                  ButtonSegment(
                    value: LessonQuestionTarget.teacher,
                    label: Text('先生に質問'),
                  ),
                  ButtonSegment(
                    value: LessonQuestionTarget.everyone,
                    label: Text('全員に質問'),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (selection) {
                  setState(() {
                    _target = selection.first;
                    if (_target == LessonQuestionTarget.everyone) {
                      _visibility = LessonQuestionVisibility.public;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('他の学習者にも公開する'),
                subtitle: const Text('オフの場合は先生にだけ公開されます。'),
                value: _visibility == LessonQuestionVisibility.public,
                onChanged: _target == LessonQuestionTarget.everyone
                    ? null
                    : (value) {
                        setState(() {
                          _visibility = value
                              ? LessonQuestionVisibility.public
                              : LessonQuestionVisibility.teacherOnly;
                        });
                      },
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<LessonNote>>(
                stream: widget.quotableNotesStream,
                builder: (context, snapshot) {
                  final notes = snapshot.data ?? const <LessonNote>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _quotedNoteId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '引用する公開メモ',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('引用なし')),
                      for (final note in notes)
                        DropdownMenuItem(
                          value: note.id ?? '',
                          child: Text(
                            note.title.isEmpty ? '無題のメモ' : note.title,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      LessonNote? selectedNote;
                      for (final note in notes) {
                        if (note.id == value) {
                          selectedNote = note;
                          break;
                        }
                      }
                      setState(() {
                        _quotedNoteId = value ?? '';
                        _quotedNoteTitle = selectedNote?.title ?? '';
                        _quotedNoteBody = selectedNote?.body ?? '';
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text('添付予定タイプ'),
              Wrap(
                spacing: 8,
                children: [
                  _QuestionAttachmentChip(
                    label: 'PDF',
                    value: lessonNoteAttachmentPdf,
                    selected: _attachmentTypes.contains(
                      lessonNoteAttachmentPdf,
                    ),
                    onSelected: _toggleAttachment,
                  ),
                  _QuestionAttachmentChip(
                    label: '画像',
                    value: lessonNoteAttachmentImage,
                    selected: _attachmentTypes.contains(
                      lessonNoteAttachmentImage,
                    ),
                    onSelected: _toggleAttachment,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: Icon(
                  widget.question?.id == null ? Icons.send : Icons.save,
                ),
                label: Text(widget.question?.id == null ? 'コメントを投稿' : '変更を保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleAttachment(String value, bool selected) {
    setState(() {
      if (selected) {
        _attachmentTypes.add(value);
      } else {
        _attachmentTypes.remove(value);
      }
    });
  }
}

class _QuestionAttachmentChip extends StatelessWidget {
  const _QuestionAttachmentChip({
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

class _LessonQuestionDraft {
  const _LessonQuestionDraft({
    required this.questionId,
    required this.body,
    required this.visibility,
    required this.target,
    required this.attachmentTypes,
    required this.quotedNoteId,
    required this.quotedNoteTitle,
    required this.quotedNoteBody,
    required this.wasPublic,
  });

  final String? questionId;
  final String body;
  final LessonQuestionVisibility visibility;
  final LessonQuestionTarget target;
  final List<String> attachmentTypes;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
  final bool wasPublic;
}

class _LessonQuestionAnswerDraft {
  const _LessonQuestionAnswerDraft({
    required this.body,
    required this.parentCommentId,
    required this.parentCommentType,
    required this.replyToAuthorId,
    required this.replyToDisplayName,
    required this.replyToBodyPreview,
    required this.quotedNoteId,
    required this.quotedNoteTitle,
    required this.quotedNoteBody,
  });

  final String body;
  final String? parentCommentId;
  final String parentCommentType;
  final String? replyToAuthorId;
  final String? replyToDisplayName;
  final String? replyToBodyPreview;
  final String? quotedNoteId;
  final String? quotedNoteTitle;
  final String? quotedNoteBody;
}
