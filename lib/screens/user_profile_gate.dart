import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'firestore_setup_page.dart';
import 'home_page.dart';
import 'suspended_account_page.dart';
import 'user_type_selection_page.dart';

class UserProfileGate extends StatelessWidget {
  const UserProfileGate({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: userDoc.get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return FirestoreSetupPage(error: snapshot.error!);
        }

        final profile = snapshot.data?.data();
        if (profile == null || profile['intendedUse'] == null) {
          return UserTypeSelectionPage(user: user);
        }

        if (profile['status'] == 'suspended') {
          return const SuspendedAccountPage();
        }

        return HomePage(user: user, profile: profile);
      },
    );
  }
}
