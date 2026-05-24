import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SuspendedAccountPage extends StatelessWidget {
  const SuspendedAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アカウント停止中')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 72),
            const SizedBox(height: 16),
            const Text(
              'このアカウントは現在利用停止中です。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              '心当たりがない場合は、運営者にお問い合わせください。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('ログアウト'),
            ),
          ],
        ),
      ),
    );
  }
}
