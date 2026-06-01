import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/public_user_profile.dart';

class PublicUserProfilePage extends StatelessWidget {
  const PublicUserProfilePage({
    super.key,
    required this.userId,
    required this.role,
    this.fallbackDisplayName,
  });

  final String userId;
  final String role;
  final String? fallbackDisplayName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: SafeArea(
        child: StreamBuilder<PublicUserProfile>(
          stream: publicUserProfileStream(
            userId: userId,
            role: role,
            fallbackDisplayName: fallbackDisplayName,
          ),
          builder: (context, snapshot) {
            final profile =
                snapshot.data ??
                fallbackPublicUserProfile(
                  userId: userId,
                  role: role,
                  displayName: fallbackDisplayName,
                );
            return Padding(
              padding: const EdgeInsets.all(24),
              child: _PublicProfileBody(profile: profile),
            );
          },
        ),
      ),
    );
  }
}

class EditPublicUserProfilePage extends StatefulWidget {
  const EditPublicUserProfilePage({
    super.key,
    required this.userId,
    required this.role,
    required this.initialProfile,
  });

  final String userId;
  final String role;
  final PublicUserProfile initialProfile;

  @override
  State<EditPublicUserProfilePage> createState() =>
      _EditPublicUserProfilePageState();
}

class _EditPublicUserProfilePageState extends State<EditPublicUserProfilePage> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late String _avatarColorName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialProfile.displayName,
    );
    _bioController = TextEditingController(text: widget.initialProfile.bio);
    _avatarColorName = widget.initialProfile.avatarColorName;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('表示名を入力してください。')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (Firebase.apps.isEmpty) {
        throw StateError('Firebaseが設定されていません。');
      }
      await FirebaseFirestore.instance
          .collection('publicUserProfiles')
          .doc(publicUserProfileDocumentId(widget.userId, widget.role))
          .set({
            'userId': widget.userId,
            'role': widget.role,
            'displayName': displayName,
            'avatarColorName': _avatarColorName,
            'bio': _bioController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('プロフィール保存に失敗しました: $error')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール編集')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _displayNameController,
              maxLength: 40,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '表示名',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              maxLength: 160,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '自己紹介',
              ),
            ),
            const SizedBox(height: 12),
            const Text('アイコン色'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in profileAvatarColors.entries)
                  ChoiceChip(
                    label: Text(_colorLabel(entry.key)),
                    selected: _avatarColorName == entry.key,
                    avatar: CircleAvatar(backgroundColor: entry.value),
                    onSelected: (_) {
                      setState(() => _avatarColorName = entry.key);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showPublicUserProfilePreview({
  required BuildContext context,
  required String userId,
  required String role,
  required String? fallbackDisplayName,
  required bool isOwner,
}) {
  if (isOwner) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    return Future.value();
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return StreamBuilder<PublicUserProfile>(
        stream: publicUserProfileStream(
          userId: userId,
          role: role,
          fallbackDisplayName: fallbackDisplayName,
        ),
        builder: (context, snapshot) {
          final profile =
              snapshot.data ??
              fallbackPublicUserProfile(
                userId: userId,
                role: role,
                displayName: fallbackDisplayName,
              );
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PublicProfileBody(profile: profile, compact: true),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PublicUserProfilePage(
                          userId: userId,
                          role: role,
                          fallbackDisplayName: fallbackDisplayName,
                        ),
                      ),
                    );
                  },
                  child: const Text('プロフィールを表示'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class PublicProfileAvatar extends StatelessWidget {
  const PublicProfileAvatar({
    super.key,
    required this.profile,
    this.radius = 20,
  });

  final PublicUserProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: profile.avatarColor,
      child: Text(profile.initial, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _PublicProfileBody extends StatelessWidget {
  const _PublicProfileBody({required this.profile, this.compact = false});

  final PublicUserProfile profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final roleLabel = profile.role == publicUserProfileRoleTeacher
        ? '先生'
        : '学習者';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: PublicProfileAvatar(profile: profile, radius: 36)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            profile.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Center(child: Text(roleLabel)),
        if (!compact)
          const SizedBox(height: 24)
        else
          const SizedBox(height: 12),
        Text(profile.bio.trim().isEmpty ? '自己紹介はまだありません。' : profile.bio),
      ],
    );
  }
}

String _colorLabel(String colorName) {
  return switch (colorName) {
    'blue' => '青',
    'green' => '緑',
    'orange' => 'オレンジ',
    'purple' => '紫',
    'pink' => 'ピンク',
    'teal' => '青緑',
    'brown' => '茶',
    'indigo' => '藍',
    _ => colorName,
  };
}
