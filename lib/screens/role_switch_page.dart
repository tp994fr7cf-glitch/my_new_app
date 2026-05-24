import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_profile_gate.dart';

class RoleSwitchPage extends StatefulWidget {
  const RoleSwitchPage({super.key, required this.user, required this.roles});

  final User user;
  final List<String> roles;

  @override
  State<RoleSwitchPage> createState() => _RoleSwitchPageState();
}

class _RoleSwitchPageState extends State<RoleSwitchPage> {
  bool _isSaving = false;
  String? _message;

  String _roleLabel(String role) {
    return switch (role) {
      'student' => '学習者',
      'teacher' => '先生',
      'schoolAdmin' => '学校・組織管理者',
      'admin' => '運営管理者',
      _ => role,
    };
  }

  String _roleDescription(String role) {
    return switch (role) {
      'student' => '講座を探したり、動画を見たりする利用者として使います。',
      'teacher' => '講座や授業を提供する先生として使います。',
      'schoolAdmin' => '学校・塾・企業などの組織管理者として使います。',
      'admin' => 'アプリ全体を管理する運営管理者として使います。',
      _ => 'この立場でアプリを使います。',
    };
  }

  Future<void> _switchRole(String role) async {
    if (!widget.roles.contains(role)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
            'activeRole': role,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => UserProfileGate(user: widget.user)),
          (route) => false,
        );
      }
    } on FirebaseException catch (error) {
      setState(() {
        _message = error.message ?? '立場の切り替えに失敗しました。';
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
      appBar: AppBar(title: const Text('立場の切り替え')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '今回はどの立場で利用しますか？',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('承認済みの権限だけがここに表示されます。'),
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
            for (final role in widget.roles) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_circle),
                  title: Text(_roleLabel(role)),
                  subtitle: Text(_roleDescription(role)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isSaving ? null : () => _switchRole(role),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
