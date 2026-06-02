import 'package:flutter/material.dart';

class CommentIdentity {
  const CommentIdentity({
    required this.displayName,
    required this.color,
    required this.isTeacher,
  });

  final String displayName;
  final Color color;
  final bool isTeacher;
}

CommentIdentity commentIdentityFor({
  required String authorId,
  required String authorName,
  String? authorDisplayName,
  String? authorRole,
}) {
  final isTeacher = authorRole == 'teacher' || authorName == '先生';
  final displayName = isTeacher
      ? (authorDisplayName?.trim().isNotEmpty == true
            ? authorDisplayName!.trim()
            : '先生')
      : _studentDisplayName(
          authorId: authorId,
          authorName: authorName,
          authorDisplayName: authorDisplayName,
        );

  return CommentIdentity(
    displayName: displayName,
    color: _stableColor(authorId.isNotEmpty ? authorId : authorName),
    isTeacher: isTeacher,
  );
}

String _studentDisplayName({
  required String authorId,
  required String authorName,
  required String? authorDisplayName,
}) {
  if (authorDisplayName != null && authorDisplayName.trim().isNotEmpty) {
    return authorDisplayName.trim();
  }
  // Temporary client-side mapping until persisted displayNumber is populated.
  if (authorName == 'naonaonaoya70833@gmail.com') {
    return '1';
  }
  if (authorName == 'naonaonaoya7083@icloud.com') {
    return '2';
  }
  final match = RegExp(r'^\d+$').firstMatch(authorName.trim());
  if (match != null) {
    return authorName.trim();
  }
  if (authorId.isEmpty) {
    return authorName.isEmpty ? '学習者' : authorName;
  }
  return ((_stableHash(authorId) % 99) + 1).toString();
}

Color _stableColor(String seed) {
  final colors = <Color>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
  ];
  return colors[_stableHash(seed) % colors.length];
}

int _stableHash(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = 0x1fffffff & (hash + codeUnit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  return hash.abs();
}
