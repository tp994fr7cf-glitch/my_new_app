import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/firebase_setup_page.dart';

final _memoryPressureObserver = _AppMemoryPressureObserver();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addObserver(_memoryPressureObserver);
  await pdfrxFlutterInitialize();

  Object? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    firebaseError = error;
  }

  runApp(MyApp(firebaseError: firebaseError));
}

class _AppMemoryPressureObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.firebaseError});

  final Object? firebaseError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learning Platform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
      ),
      home: firebaseError == null
          ? const AuthGate()
          : FirebaseSetupPage(error: firebaseError!),
    );
  }
}
