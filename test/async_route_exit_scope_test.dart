import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_app/widgets/async_route_exit_scope.dart';

void main() {
  testWidgets('waits for cleanup before leaving a route', (tester) async {
    final cleanup = Completer<void>();
    var cleanupCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AsyncRouteExitScope(
                      progressLabel: 'closing',
                      onExit: () {
                        cleanupCalls += 1;
                        return cleanup.future;
                      },
                      child: const Scaffold(body: Text('protected route')),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(cleanupCalls, 1);
    expect(find.text('protected route'), findsOneWidget);
    expect(find.text('closing'), findsOneWidget);

    cleanup.complete();
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(find.text('protected route'), findsNothing);
  });

  testWidgets('busy overlay blocks interaction until saving finishes', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AsyncRouteExitScope(
          onExit: () async {},
          busyLabel: 'サーバーへ保存しています',
          child: Scaffold(
            body: FilledButton(
              onPressed: () => tapped = true,
              child: const Text('room action'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('サーバーへ保存しています'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('room action'), warnIfMissed: false);
    await tester.pump();
    expect(tapped, isFalse);
  });

  testWidgets('busy overlay keeps saving label while route cleanup runs', (
    tester,
  ) async {
    final cleanup = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AsyncRouteExitScope(
                      progressLabel: '配信との接続を終了しています…',
                      busyLabel: 'サーバーへ保存しています',
                      onExit: () => cleanup.future,
                      child: const Scaffold(body: Text('live room')),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    expect(find.text('live room'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('サーバーへ保存しています'), findsOneWidget);
    expect(find.text('配信との接続を終了しています…'), findsNothing);
    expect(find.text('live room'), findsOneWidget);

    cleanup.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('leaves the route if cleanup never finishes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AsyncRouteExitScope(
                      progressLabel: 'closing',
                      exitTimeout: const Duration(milliseconds: 50),
                      onExit: () => Completer<void>().future,
                      child: const Scaffold(body: Text('protected route')),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('protected route'), findsOneWidget);
    expect(find.text('closing'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(find.text('protected route'), findsNothing);
  });
}
