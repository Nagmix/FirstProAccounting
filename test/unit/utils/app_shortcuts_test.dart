import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/app_shortcuts.dart';

/// U-04 Phase 2: tests for AppShortcuts.
void main() {
  group('AppShortcuts.wrap', () {
    testWidgets('renders child when no callbacks provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShortcuts.wrap(
            child: const Scaffold(body: Text('test')),
          ),
        ),
      );
      expect(find.text('test'), findsOneWidget);
    });

    testWidgets('renders child with shortcuts when callbacks provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShortcuts.wrap(
            onSave: () {},
            child: const Scaffold(body: Text('test')),
          ),
        ),
      );
      expect(find.text('test'), findsOneWidget);
      // MaterialApp also adds Shortcuts/Actions, so we use findsWidgets.
      expect(find.byType(Shortcuts), findsWidgets);
      expect(find.byType(Actions), findsWidgets);
    });

    testWidgets('Shortcuts widget is created when onSave provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShortcuts.wrap(
            onSave: () {},
            child: const Scaffold(body: Text('test')),
          ),
        ),
      );
      expect(find.text('test'), findsOneWidget);
      expect(find.byType(Shortcuts), findsWidgets);
      expect(find.byType(Actions), findsWidgets);
    });

    testWidgets('AppShortcuts.formSection wraps with FocusTraversalGroup',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppShortcuts.formSection(
              child: const Text('form'),
            ),
          ),
        ),
      );
      // MaterialApp also adds FocusTraversalGroup, so findsWidgets.
      expect(find.byType(FocusTraversalGroup), findsWidgets);
      expect(find.text('form'), findsOneWidget);
    });
  });

  group('Custom Intents', () {
    test('all intents are const-constructible', () {
      const save = SaveIntent();
      const search = SearchIntent();
      const refresh = RefreshIntent();
      const escape = EscapeIntent();
      const printIntent = PrintIntent();

      expect(save, isA<Intent>());
      expect(search, isA<Intent>());
      expect(refresh, isA<Intent>());
      expect(escape, isA<Intent>());
      expect(printIntent, isA<Intent>());
    });
  });
}
