import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CourseCreatePage extends StatefulWidget {
  const CourseCreatePage({super.key, required this.user});

  final User user;

  @override
  State<CourseCreatePage> createState() => _CourseCreatePageState();
}

class _CourseCreatePageState extends State<CourseCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _levelController = TextEditingController(text: '初心者向け');
  final _descriptionController = TextEditingController();
  final _priceLabelController = TextEditingController(text: '無料');
  final _lessonControllers = [
    TextEditingController(text: 'レッスン1'),
    TextEditingController(text: 'レッスン2'),
    TextEditingController(text: 'レッスン3'),
  ];

  bool _isSaving = false;
  String? _message;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _levelController.dispose();
    _descriptionController.dispose();
    _priceLabelController.dispose();
    for (final controller in _lessonControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '入力してください';
    }
    return null;
  }

  String _generateCourseCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  List<Map<String, dynamic>> _lessons() {
    return _lessonControllers
        .map((controller) => controller.text.trim())
        .where((title) => title.isNotEmpty)
        .map(
          (title) => {
            'title': title,
            'duration': '1分30秒',
            'mediaType': 'video',
            'mediaUrl': '',
            'isPreview': false,
          },
        )
        .toList();
  }

  Future<void> _saveCourse() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final lessons = _lessons();
    if (lessons.isEmpty) {
      setState(() {
        _message = 'レッスンを1つ以上入力してください。';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final courseCode = _generateCourseCode();
      final docRef = FirebaseFirestore.instance.collection('courses').doc();
      await docRef.set({
        'courseCode': courseCode,
        'title': _titleController.text.trim(),
        'instructorId': widget.user.uid,
        'instructorName': widget.user.displayName ?? widget.user.email ?? '先生',
        'category': _categoryController.text.trim(),
        'level': _levelController.text.trim(),
        'duration': '${lessons.length}レッスン',
        'lessonCount': lessons.length,
        'rating': 0,
        'priceLabel': _priceLabelController.text.trim(),
        'description': _descriptionController.text.trim(),
        'lessons': lessons,
        'lessonEvents': [],
        'status': 'published',
        'source': 'teacherCreated',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('講座を作成しました。講座コード: $courseCode')),
          );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message ?? '講座の保存に失敗しました。';
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
      appBar: AppBar(title: const Text('講座作成')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '新しい講座を作成',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('保存すると講座コードが自動発行され、学習者の講座一覧に表示されます。'),
              const SizedBox(height: 24),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '講座タイトル',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'カテゴリ',
                  hintText: '例: 数学、英語、プログラミング',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _levelController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'レベル',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceLabelController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '価格表示',
                  hintText: '例: 無料、¥1,200、サブスク対象',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '講座説明',
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 24),
              const Text(
                'レッスン構成',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (
                var index = 0;
                index < _lessonControllers.length;
                index++
              ) ...[
                TextFormField(
                  controller: _lessonControllers[index],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'レッスン${index + 1}',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_message != null) ...[
                const SizedBox(height: 4),
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
                onPressed: _isSaving ? null : _saveCourse,
                icon: const Icon(Icons.save),
                label: const Text('講座を保存する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
