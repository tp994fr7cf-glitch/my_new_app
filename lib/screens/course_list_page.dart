import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import 'course_detail_page.dart';

class CourseListPage extends StatefulWidget {
  const CourseListPage({super.key, this.courseStream});

  final Stream<List<Course>>? courseStream;

  @override
  State<CourseListPage> createState() => _CourseListPageState();
}

class _CourseListPageState extends State<CourseListPage> {
  final _searchController = TextEditingController();
  bool _isSeeding = false;
  String? _message;

  String get _searchText => _searchController.text.trim();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<Course>> _coursesStream() {
    final providedStream = widget.courseStream;
    if (providedStream != null) {
      return providedStream;
    }

    return FirebaseFirestore.instance
        .collection('courses')
        .where('status', isEqualTo: 'published')
        .snapshots()
        .map((snapshot) {
          final courses = snapshot.docs.map(Course.fromFirestore).toList();
          courses.sort((a, b) => a.title.compareTo(b.title));
          return courses;
        });
  }

  Future<void> _seedSampleCourses() async {
    setState(() {
      _isSeeding = true;
      _message = null;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final coursesRef = FirebaseFirestore.instance.collection('courses');

      for (final course in sampleCourses) {
        final docRef = coursesRef.doc(course.id);
        batch.set(docRef, {
          ...course.toFirestore(),
          'status': 'published',
          'source': 'developmentSeed',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        setState(() {
          _message = 'サンプル講座をFirestoreに登録しました。';
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message ?? 'サンプル講座の登録に失敗しました。';
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
          _isSeeding = false;
        });
      }
    }
  }

  List<Course> _filteredCourses(List<Course> courses) {
    final query = _searchText.toLowerCase();
    if (query.isEmpty) {
      return courses;
    }

    return courses.where((course) {
      return course.title.toLowerCase().contains(query) ||
          course.instructorName.toLowerCase().contains(query) ||
          course.category.toLowerCase().contains(query) ||
          course.level.toLowerCase().contains(query) ||
          (course.courseCode?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _saveSearchHistory(String keyword) async {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty || widget.courseStream != null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('courseSearchHistory')
          .doc(normalizedKeyword.toLowerCase())
          .set({
            'keyword': normalizedKeyword,
            'normalizedKeyword': normalizedKeyword.toLowerCase(),
            'searchedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // 検索自体を優先するため、履歴保存の失敗は画面操作を止めない。
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _searchHistoryStream() {
    if (widget.courseStream != null) {
      return null;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('courseSearchHistory')
        .orderBy('searchedAt', descending: true)
        .limit(5)
        .snapshots();
  }

  void _applySearch(String value) {
    setState(() {});
    _saveSearchHistory(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('講座一覧')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '学びたい講座を探す',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Firestoreに保存されている公開講座を表示します。'),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchText.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                labelText: '講座コード・講座名・先生名・カテゴリで検索',
              ),
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: _applySearch,
            ),
            _SearchHistoryChips(
              historyStream: _searchHistoryStream(),
              onSelected: (keyword) {
                _searchController.text = keyword;
                _applySearch(keyword);
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('すべて')),
                Chip(label: Text('プログラミング')),
                Chip(label: Text('数学')),
                Chip(label: Text('英語')),
                Chip(label: Text('企業研修')),
              ],
            ),
            const SizedBox(height: 24),
            if (_message != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
              const SizedBox(height: 16),
            ],
            StreamBuilder<List<Course>>(
              stream: _coursesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _CourseLoadError(error: snapshot.error!);
                }

                final courses = snapshot.data ?? const [];
                final filteredCourses = _filteredCourses(courses);
                if (courses.isEmpty) {
                  return _EmptyCoursesCard(
                    isSeeding: _isSeeding,
                    onSeedPressed: widget.courseStream == null
                        ? _seedSampleCourses
                        : null,
                  );
                }

                if (filteredCourses.isEmpty) {
                  return _NoSearchResultsCard(query: _searchText);
                }

                return Column(
                  children: [
                    for (final course in filteredCourses) ...[
                      _CourseCard(course: course),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHistoryChips extends StatelessWidget {
  const _SearchHistoryChips({
    required this.historyStream,
    required this.onSelected,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>>? historyStream;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final stream = historyStream;
    if (stream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final keywords =
            snapshot.data?.docs
                .map((doc) => doc.data()['keyword'])
                .whereType<String>()
                .where((keyword) => keyword.isNotEmpty)
                .toList() ??
            const <String>[];

        if (keywords.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Chip(label: Text('検索履歴')),
              for (final keyword in keywords)
                ActionChip(
                  label: Text(keyword),
                  onPressed: () => onSelected(keyword),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NoSearchResultsCard extends StatelessWidget {
  const _NoSearchResultsCard({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('「$query」に一致する講座は見つかりませんでした。'),
      ),
    );
  }
}

class _CourseLoadError extends StatelessWidget {
  const _CourseLoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '講座データの読み込みに失敗しました: $error',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _EmptyCoursesCard extends StatelessWidget {
  const _EmptyCoursesCard({
    required this.isSeeding,
    required this.onSeedPressed,
  });

  final bool isSeeding;
  final VoidCallback? onSeedPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'まだ講座がありません',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('開発確認用に、サンプル講座をFirestoreへ登録できます。'),
            if (isSeeding) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isSeeding ? null : onSeedPressed,
              icon: const Icon(Icons.add),
              label: const Text('サンプル講座を登録する'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final Course course;

  void _openCourseDetail(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CourseDetailPage(course: course)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openCourseDetail(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.ondemand_video,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(course.category)),
                  Chip(label: Text(course.level)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                course.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (course.courseCode != null) ...[
                const SizedBox(height: 4),
                Text('講座コード: ${course.courseCode}'),
              ],
              const SizedBox(height: 4),
              Text('講師: ${course.instructorName}'),
              const SizedBox(height: 8),
              Text(course.description),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.star, size: 18),
                  const SizedBox(width: 4),
                  Text(course.rating.toStringAsFixed(1)),
                  const SizedBox(width: 16),
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 4),
                  Text(course.duration),
                  const SizedBox(width: 16),
                  const Icon(Icons.list_alt, size: 18),
                  const SizedBox(width: 4),
                  Text('${course.lessonCount}本'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    course.priceLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      _openCourseDetail(context);
                    },
                    child: const Text('詳細を見る'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
