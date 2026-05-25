import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TeacherApplicationFormPage extends StatefulWidget {
  const TeacherApplicationFormPage({
    super.key,
    required this.user,
    required this.initialDisplayName,
  });

  final User user;
  final String initialDisplayName;

  @override
  State<TeacherApplicationFormPage> createState() =>
      _TeacherApplicationFormPageState();
}

class _TeacherApplicationFormPageState
    extends State<TeacherApplicationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  final _specialtyController = TextEditingController();
  final _experienceController = TextEditingController();
  final _reasonController = TextEditingController();
  final _referenceUrlController = TextEditingController();

  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialDisplayName,
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _specialtyController.dispose();
    _experienceController.dispose();
    _reasonController.dispose();
    _referenceUrlController.dispose();
    super.dispose();
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '入力してください';
    }
    return null;
  }

  String _firebaseErrorMessage(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' => '先生申請を送信する権限がありません。ログイン状態やFirestoreルールを確認してください。',
      'unavailable' => 'ネットワークに接続できません。通信状態を確認してからもう一度お試しください。',
      _ => error.message ?? '先生申請の送信に失敗しました。',
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
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
            'intendedUse': 'teacher',
            'teacherApplicationStatus': 'pending',
            'teacherApplication': {
              'displayName': _displayNameController.text.trim(),
              'specialty': _specialtyController.text.trim(),
              'experience': _experienceController.text.trim(),
              'reason': _reasonController.text.trim(),
              'referenceUrl': _referenceUrlController.text.trim(),
              'submittedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = _firebaseErrorMessage(error);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'エラーが発生しました: $error';
        });
      }
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
      appBar: AppBar(title: const Text('先生情報の入力')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '先生として申請する',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('運営者が確認するため、専門分野や講師経験、申請理由を入力してください。'),
              const SizedBox(height: 24),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '氏名または表示名',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _specialtyController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '専門分野',
                  hintText: '例: 数学、英語、Flutter、企業研修',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _experienceController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '講師経験',
                  hintText: '例: 塾講師3年、社内研修担当、個別指導など',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '申請理由',
                  hintText: 'どのような講座を提供したいかを書いてください。',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _referenceUrlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '補足URLまたは実績URL（任意）',
                  hintText: 'ポートフォリオ、SNS、学校・企業ページなど',
                ),
                keyboardType: TextInputType.url,
              ),
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
              if (_isSaving) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: const Icon(Icons.send),
                label: const Text('申請を送信する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
