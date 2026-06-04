import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/lesson_note.dart';

Future<void> showPublicNoteEditHistorySheet(
  BuildContext context, {
  required String noteId,
  required String fallbackTitle,
  required String fallbackBody,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PublicNoteEditHistorySheet(
      noteId: noteId,
      fallbackTitle: fallbackTitle,
      fallbackBody: fallbackBody,
    ),
  );
}

class PublicNoteEditStatusButton extends StatelessWidget {
  const PublicNoteEditStatusButton({
    super.key,
    required this.noteId,
    required this.fallbackTitle,
    required this.fallbackBody,
    this.icon = Icons.note_alt_outlined,
    this.leadingLabel = 'メモ状態',
  });

  final String? noteId;
  final String fallbackTitle;
  final String fallbackBody;
  final IconData icon;
  final String leadingLabel;

  @override
  Widget build(BuildContext context) {
    final safeNoteId = (noteId ?? '').trim();
    if (safeNoteId.isEmpty) {
      return const SizedBox.shrink();
    }
    if (Firebase.apps.isEmpty) {
      return TextButton.icon(
        onPressed: () {
          showPublicNoteEditHistorySheet(
            context,
            noteId: safeNoteId,
            fallbackTitle: fallbackTitle,
            fallbackBody: fallbackBody,
          );
        },
        icon: Icon(icon, size: 18),
        label: Text('$leadingLabel: 状態確認'),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicLessonNotes')
          .doc(safeNoteId)
          .snapshots(),
      builder: (context, snapshot) {
        final noteData = snapshot.data?.data();
        final note = noteData == null
            ? null
            : LessonNote.fromMap(noteData, id: snapshot.data?.id);
        final hasEdits = note?.hasCitationEdits == true;
        final label = hasEdits ? '編集済' : '未編集';
        return TextButton.icon(
          onPressed: () {
            showPublicNoteEditHistorySheet(
              context,
              noteId: safeNoteId,
              fallbackTitle: note?.title ?? fallbackTitle,
              fallbackBody: note?.body ?? fallbackBody,
            );
          },
          icon: Icon(icon, size: 18),
          label: Text('$leadingLabel: $label'),
        );
      },
    );
  }
}

class _PublicNoteEditHistorySheet extends StatelessWidget {
  const _PublicNoteEditHistorySheet({
    required this.noteId,
    required this.fallbackTitle,
    required this.fallbackBody,
  });

  final String noteId;
  final String fallbackTitle;
  final String fallbackBody;

  @override
  Widget build(BuildContext context) {
    final historyStream = Firebase.apps.isEmpty
        ? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
            .collection('publicLessonNotes')
            .doc(noteId)
            .collection(publicLessonNoteEditHistoryCollection)
            .orderBy('editedAt', descending: true)
            .limit(100)
            .snapshots();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'メモ編集履歴',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: Firebase.apps.isEmpty
                  ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
                  : FirebaseFirestore.instance
                      .collection('publicLessonNotes')
                      .doc(noteId)
                      .snapshots(),
              builder: (context, noteSnapshot) {
                final noteData = noteSnapshot.data?.data();
                final note = noteData == null
                    ? null
                    : LessonNote.fromMap(noteData, id: noteSnapshot.data?.id);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    note?.hasCitationEdits == true
                        ? '状態: 編集済（${note?.citationEditCount ?? 0}回）'
                        : '状態: 未編集',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: historyStream,
                builder: (context, snapshot) {
                  final entries = (snapshot.data?.docs ?? const [])
                      .map(LessonNoteEditHistoryEntry.fromFirestore)
                      .toList()
                    ..sort((a, b) {
                      final aAt = a.editedAt?.toDate() ?? DateTime(1970);
                      final bAt = b.editedAt?.toDate() ?? DateTime(1970);
                      return bAt.compareTo(aAt);
                    });
                  if (entries.isEmpty) {
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        Text(
                          '編集履歴はまだありません。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final editedAt = _formatEditTimestamp(entry.editedAt);
                      final canCompare =
                          entry.compareAvailable &&
                          entry.beforeTitle != null &&
                          entry.beforeBody != null &&
                          entry.afterTitle != null &&
                          entry.afterBody != null &&
                          !isPublicNoteHistoryComparisonExpired(
                            nowUtc: DateTime.now().toUtc(),
                            compareVisibleUntil: entry.compareVisibleUntil,
                          );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('編集日時: $editedAt'),
                        subtitle: Text(
                          canCompare ? '比較可能（7日以内）' : '比較データなし',
                        ),
                        trailing: canCompare
                            ? TextButton(
                                onPressed: () {
                                  _showHistoryCompareDialog(
                                    context,
                                    entry: entry,
                                    fallbackTitle: fallbackTitle,
                                    fallbackBody: fallbackBody,
                                  );
                                },
                                child: const Text('比較'),
                              )
                            : null,
                      );
                    },
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemCount: entries.length,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showHistoryCompareDialog(
  BuildContext context, {
  required LessonNoteEditHistoryEntry entry,
  required String fallbackTitle,
  required String fallbackBody,
}) {
  final beforeTitle = (entry.beforeTitle ?? '').isEmpty
      ? '無題のメモ'
      : entry.beforeTitle!;
  final beforeBody = (entry.beforeBody ?? '').isEmpty ? '本文なし' : entry.beforeBody!;
  final afterTitle = (entry.afterTitle ?? '').isEmpty
      ? (fallbackTitle.isEmpty ? '無題のメモ' : fallbackTitle)
      : entry.afterTitle!;
  final afterBody = (entry.afterBody ?? '').isEmpty
      ? (fallbackBody.isEmpty ? '本文なし' : fallbackBody)
      : entry.afterBody!;
  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('編集前後の比較'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '編集前',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text('タイトル: $beforeTitle'),
              Text('本文: $beforeBody'),
              const SizedBox(height: 12),
              Text(
                '編集後',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text('タイトル: $afterTitle'),
              Text('本文: $afterBody'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      );
    },
  );
}

String _formatEditTimestamp(Timestamp? timestamp) {
  if (timestamp == null) {
    return '記録時刻不明';
  }
  final dateTime = timestamp.toDate().toLocal();
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}/${dateTime.month}/${dateTime.day} $hour:$minute';
}

bool isPublicNoteHistoryComparisonExpired({
  required DateTime nowUtc,
  required Timestamp? compareVisibleUntil,
}) {
  if (compareVisibleUntil == null) {
    return true;
  }
  return nowUtc.isAfter(compareVisibleUntil.toDate().toUtc());
}
