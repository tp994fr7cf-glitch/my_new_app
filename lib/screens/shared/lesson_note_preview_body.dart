import 'package:flutter/material.dart';

import '../../models/lesson_note.dart';
import '../../models/public_user_profile.dart';
import '../public_user_profile_page.dart';

class LessonNotePreviewBody extends StatelessWidget {
  const LessonNotePreviewBody({
    super.key,
    required this.note,
    required this.canCreateQuestion,
    this.onCreateQuestion,
    this.onEdit,
  });

  final LessonNote note;
  final bool canCreateQuestion;
  final VoidCallback? onCreateQuestion;
  final Future<void> Function(BuildContext context)? onEdit;

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
                        formatPublicNoteTimestamp(note),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            const SizedBox(height: 24),
            if (canCreateQuestion &&
                note.allowsQuestionCitation &&
                onCreateQuestion != null) ...[
              FilledButton.icon(
                onPressed: onCreateQuestion,
                icon: const Icon(Icons.add_comment),
                label: const Text('このメモを引用して質問する'),
              ),
            ] else if (canCreateQuestion && !note.allowsQuestionCitation) ...[
              const Text('このメモの作成者は引用を許可していません。'),
            ],
            if (onEdit != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await onEdit!.call(context);
                },
                icon: const Icon(Icons.edit),
                label: const Text('このメモを編集'),
              ),
            ],
          ],
        );
      },
    );
  }
}

String formatPublicNoteTimestamp(LessonNote note) {
  final timestamp = lessonNotePostedAt(note);
  if (timestamp == null) {
    return '投稿日時不明';
  }
  final dateTime = timestamp.toDate().toLocal();
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}
