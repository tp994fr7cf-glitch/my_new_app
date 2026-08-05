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
}
