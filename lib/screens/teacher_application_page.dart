import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'teacher_application_form_page.dart';

class TeacherApplicationPage extends StatefulWidget {
  const TeacherApplicationPage({
    super.key,
    required this.user,
    required this.profile,
    this.profileStream,
  });

  final User user;
  final Map<String, dynamic> profile;
  final Stream<Map<String, dynamic>>? profileStream;

  @override
  State<TeacherApplicationPage> createState() => _TeacherApplicationPageState();
}

class _TeacherApplicationPageState extends State<TeacherApplicationPage> {
  String? _message;
  Map<String, dynamic>? _latestProfile;
  Timer? _messageTimer;

  Map<String, dynamic> get _profile => _latestProfile ?? widget.profile;

  String get _status {
    final status = _profile['teacherApplicationStatus'];
    return status is String ? status : 'none';
  }

  List<String> get _roles {
    final roles = _profile['roles'];
    if (roles is List) {
      return roles.whereType<String>().toList();
    }
    return const ['student'];
  }

  bool get _canApply {
    return !_roles.contains('teacher') && _status == 'none';
  }

  String _statusLabel(String status) {
    return switch (status) {
      'pending' => '申請中',
      'approved' => '承認済み',
      'rejected' => '申請却下',
      'none' => '未申請',
      _ => '未申請',
    };
  }

  String _statusDescription(String status) {
    if (_roles.contains('teacher') || status == 'approved') {
      return '先生権限は承認済みです。立場切替から先生として利用できるようになります。';
    }

    return switch (status) {
      'pending' => '先生申請を受け付けました。運営者の確認が終わるまでお待ちください。',
      'rejected' => '前回の申請は承認されませんでした。現在は再申請できません。',
      _ => '講座を投稿するには、先生としての申請が必要です。',
    };
  }

  void _showTemporaryMessage(String message) {
    _messageTimer?.cancel();

    setState(() {
      _message = message;
    });

    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (_message == message) {
            _message = null;
          }
        });
      }
    });
  }

  void _handleApplicationButtonPressed(BuildContext context) {
    final status = _status;

    if (status == 'pending') {
      _showTemporaryMessage('申請中です');
      return;
    }

    if (status == 'rejected') {
      _showTemporaryMessage('申請は却下されました');
      return;
    }

    if (_roles.contains('teacher') || status == 'approved') {
      _showTemporaryMessage('先生権限は承認済みです');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherApplicationFormPage(
          user: widget.user,
          initialDisplayName:
              widget.user.displayName ?? widget.user.email ?? '',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileStream =
        widget.profileStream ??
        FirebaseFirestore.instance
            .collection('users')
            .doc(widget.user.uid)
            .snapshots()
            .map((snapshot) => snapshot.data() ?? widget.profile);

    return StreamBuilder<Map<String, dynamic>>(
      stream: profileStream,
      initialData: _profile,
      builder: (context, snapshot) {
        _latestProfile = snapshot.data ?? _profile;
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: const Text('先生申請')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '先生として活動する',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('講座の投稿や受講者対応を行うには、運営者による先生権限の承認が必要です。'),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '現在の申請状況',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Chip(label: Text(_statusLabel(status))),
                    const SizedBox(height: 12),
                    Text(_statusDescription(status)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _ApplicationNotesCard(),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_canApply || status == 'pending' || status == 'rejected')
              FilledButton.icon(
                onPressed: () => _handleApplicationButtonPressed(context),
                icon: const Icon(Icons.send),
                label: const Text('先生として申請する'),
              )
            else
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('ホームへ戻る'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationNotesCard extends StatelessWidget {
  const _ApplicationNotesCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '申請後の流れ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _BulletText('申請するとステータスが「申請中」になります。'),
            _BulletText('運営者が内容を確認して、承認後に先生権限を付与します。'),
            _BulletText('承認されるまでは学習者として引き続き利用できます。'),
          ],
        ),
      ),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・'),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
