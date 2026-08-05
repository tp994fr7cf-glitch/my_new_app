import 'dart:async';

import 'package:flutter/material.dart';

class AsyncRouteExitScope extends StatefulWidget {
  const AsyncRouteExitScope({
    super.key,
    required this.onExit,
    required this.child,
    this.progressLabel = '終了処理中…',
  });

  final Future<void> Function() onExit;
  final Widget child;
  final String progressLabel;

  @override
  State<AsyncRouteExitScope> createState() => _AsyncRouteExitScopeState();
}

class _AsyncRouteExitScopeState extends State<AsyncRouteExitScope> {
  bool _allowPop = false;
  bool _isExiting = false;
  Future<void>? _exitOperation;

  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop || _allowPop) {
      return;
    }
    final existing = _exitOperation;
    if (existing != null) {
      await existing;
      return;
    }

    final operation = _exit(result);
    _exitOperation = operation;
    await operation;
  }

  Future<void> _exit(Object? result) async {
    if (mounted) {
      setState(() => _isExiting = true);
    }
    try {
      await widget.onExit();
    } catch (error, stackTrace) {
      debugPrint('Async route cleanup failed: $error\n$stackTrace');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _allowPop = true;
      _isExiting = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: _handlePop,
      child: Stack(
        children: [
          widget.child,
          if (_isExiting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(widget.progressLabel),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
