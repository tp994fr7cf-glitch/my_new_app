import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _googleServerClientId =
      '848607557123-4so07l6aq6ss8nbil142m9ufe6npolfc.apps.googleusercontent.com';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();

  String? _verificationId;
  String? _message;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _message = message;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _authErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => 'このメールアドレスはすでに登録されています。',
      'invalid-email' => 'メールアドレスの形式が正しくありません。',
      'invalid-credential' => 'メールアドレスまたはパスワードが正しくありません。',
      'operation-not-allowed' => 'Firebase Consoleでこのログイン方法を有効化してください。',
      'configuration-not-found' =>
        'Firebase Authenticationの設定がまだ完了していません。Firebase ConsoleでAuthenticationを開始し、Email/Passwordを有効化してください。',
      'internal-error' =>
        'Firebase側でSMS認証の処理に失敗しました。Phoneログインが有効か、テスト用電話番号を設定しているか確認してください。',
      'weak-password' => 'パスワードは6文字以上にしてください。',
      _ => error.message ?? '認証に失敗しました。',
    };
  }

  String _googleSignInErrorMessage(GoogleSignInException error) {
    final code = error.code.toString();

    if (code.contains('canceled')) {
      return 'Googleログインがキャンセルされました。';
    }

    if (code.contains('clientConfigurationError')) {
      return 'Googleログインの設定が不足していました。アプリを再起動して、もう一度試してください。';
    }

    return 'Googleログインに失敗しました。しばらくしてからもう一度試してください。';
  }

  bool _validateEmailAndPassword() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('メールアドレスとパスワードを入力してください。');
      return false;
    }

    if (password.length < 6) {
      _showMessage('パスワードは6文字以上にしてください。');
      return false;
    }

    return true;
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await action();
    } on GoogleSignInException catch (error) {
      _showMessage(_googleSignInErrorMessage(error));
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorMessage(error));
    } catch (error) {
      _showMessage('エラーが発生しました: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithEmail() {
    if (!_validateEmailAndPassword()) {
      return Future.value();
    }

    return _runAuthAction(() async {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    });
  }

  Future<void> _createAccountWithEmail() {
    if (!_validateEmailAndPassword()) {
      return Future.value();
    }

    return _runAuthAction(() async {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    });
  }

  Future<void> _signInWithGoogle() {
    return _runAuthAction(() async {
      await GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
      );
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    });
  }

  Future<void> _sendSmsCode() {
    if (_phoneController.text.trim().isEmpty) {
      _showMessage('電話番号を入力してください。例: +819012345678');
      return Future.value();
    }

    return _runAuthAction(() async {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _phoneController.text.trim(),
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
        },
        verificationFailed: (error) {
          _showMessage(error.message ?? 'SMS認証に失敗しました。');
        },
        codeSent: (verificationId, _) {
          _verificationId = verificationId;
          _showMessage('SMSコードを送信しました。');
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    });
  }

  Future<void> _verifySmsCode() {
    if (_smsCodeController.text.trim().isEmpty) {
      _showMessage('SMSコードを入力してください。');
      return Future.value();
    }

    return _runAuthAction(() async {
      final verificationId = _verificationId;
      if (verificationId == null) {
        _showMessage('先にSMSコードを送信してください。');
        return;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: _smsCodeController.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ログイン')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '学習プラットフォームへようこそ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('まずはログイン機能から作っていきます。', textAlign: TextAlign.center),
              if (_isLoading) ...[
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
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'メールアドレス',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'パスワード',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isLoading ? null : _signInWithEmail,
                child: const Text('メールアドレスでログイン'),
              ),
              OutlinedButton(
                onPressed: _isLoading ? null : _createAccountWithEmail,
                child: const Text('メールアドレスで新規登録'),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _isLoading ? null : _signInWithGoogle,
                icon: const Icon(Icons.account_circle),
                label: const Text('Googleアカウントでログイン'),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                '電話番号で新規登録・ログイン',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  helperText: '例: +819012345678',
                  labelText: '電話番号',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isLoading ? null : _sendSmsCode,
                child: const Text('SMSコードを送信'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _smsCodeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SMSコード',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isLoading ? null : _verifySmsCode,
                child: const Text('SMSコードでログイン'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
