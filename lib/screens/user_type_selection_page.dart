import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_profile_gate.dart';

class UserTypeSelectionPage extends StatefulWidget {
  const UserTypeSelectionPage({super.key, required this.user});

  final User user;

  @override
  State<UserTypeSelectionPage> createState() => _UserTypeSelectionPageState();
}

class _UserTypeSelectionPageState extends State<UserTypeSelectionPage> {
  bool _isSaving = false;
  String? _message;

  Future<void> _saveUserType(String intendedUse) async {
    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid);
      final currentDoc = await userDoc.get();
      final existingData = currentDoc.data();
      final existingRoles = existingData?['roles'];
      final isTeacherApplication = intendedUse == 'teacher';
      final isOrganizationApplication = intendedUse == 'organization';

      await userDoc.set({
        'uid': widget.user.uid,
        'email': widget.user.email,
        'displayName': widget.user.displayName,
        'phoneNumber': widget.user.phoneNumber,
        'photoURL': widget.user.photoURL,
        'roles': existingRoles is List && existingRoles.isNotEmpty
            ? existingRoles
            : ['student'],
        'activeRole': 'student',
        'role': 'student',
        'status': 'active',
        'intendedUse': intendedUse,
        'teacherApplicationStatus': isTeacherApplication ? 'pending' : 'none',
        'organizationApplicationStatus': isOrganizationApplication
            ? 'pending'
            : 'none',
        if (!currentDoc.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseAuth.instance.currentUser?.reload();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                UserProfileGate(user: FirebaseAuth.instance.currentUser!),
          ),
        );
      }
    } on FirebaseException catch (error) {
      setState(() {
        _message = error.message ?? 'ユーザー情報の保存に失敗しました。';
      });
    } catch (error) {
      setState(() {
        _message = 'エラーが発生しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('利用目的の選択'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'どのようにアプリを利用しますか？',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('先生や組織の権限は、ここで選んだだけでは付与されません。申請として保存し、運営者が後から承認します。'),
            if (_isSaving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _UserTypeCard(
              icon: Icons.menu_book,
              title: '学習者として使う',
              description: '講座を探したり、動画を見たり、学習記録を残すための利用です。',
              onPressed: _isSaving ? null : () => _saveUserType('learner'),
            ),
            const SizedBox(height: 12),
            _UserTypeCard(
              icon: Icons.school,
              title: '先生として申請する',
              description: '講座や授業を提供したい方向けです。運営者の承認後に先生権限を付与します。',
              onPressed: _isSaving ? null : () => _saveUserType('teacher'),
            ),
            const SizedBox(height: 12),
            _UserTypeCard(
              icon: Icons.business,
              title: '学校・塾・企業として利用する',
              description: '教育機関や企業研修として利用したい場合の申請です。運営者が後で確認します。',
              onPressed: _isSaving ? null : () => _saveUserType('organization'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserTypeCard extends StatelessWidget {
  const _UserTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            FilledButton(onPressed: onPressed, child: const Text('この内容で進む')),
          ],
        ),
      ),
    );
  }
}
