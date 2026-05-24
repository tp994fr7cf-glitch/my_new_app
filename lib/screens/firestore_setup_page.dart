import 'package:flutter/material.dart';

class FirestoreSetupPage extends StatelessWidget {
  const FirestoreSetupPage({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('データベース設定が必要です')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ユーザー種別を保存するには、Cloud Firestoreの設定が必要です。',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Firebase ConsoleでCloud Firestoreを開始し、ログイン済みユーザーが自分のユーザー情報を保存できるようにします。',
            ),
            const SizedBox(height: 24),
            Text(
              '現在のエラー:\n$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}
