import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/theme/app_theme.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/recurring_invoice_service.dart';
import 'package:firstpro/ui/screens/recurring_invoices/recurring_invoices_screen.dart';

/// P-01 Phase 2: Widget tests for RecurringInvoicesScreen.
///
/// Tests the screen's rendering (empty state, loading, list) and
/// user interactions (FAB tap, refresh) with mocked DI.
void main() {
  setUp(() {
    locator.reset();
    // Register mocks for dependencies used by the screen.
    locator.registerLazySingleton<DatabaseHelper>(() => _MockDatabaseHelper());
    locator.registerLazySingleton<InvoiceRepository>(
      () => _MockInvoiceRepository(),
    );
    locator.registerLazySingleton<ReferenceDataRepository>(
      () => _MockReferenceDataRepository(),
    );
    locator.registerLazySingleton<RecurringInvoiceService>(
      () => _MockRecurringInvoiceService(),
    );
  });

  testWidgets('shows AppBar with correct title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RecurringInvoicesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الفواتير المتكررة'), findsOneWidget);
  });

  testWidgets('shows empty state when no templates exist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RecurringInvoicesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا توجد فواتير متكررة'), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsOneWidget);
  });

  testWidgets('shows FAB for creating new template', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RecurringInvoicesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('قالب جديد'), findsOneWidget);
  });

  testWidgets('shows process button in AppBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RecurringInvoicesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('توليد الفواتير المستحقة'), findsOneWidget);
    expect(find.byTooltip('تحديث'), findsOneWidget);
  });

  testWidgets('tapping FAB opens create dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RecurringInvoicesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Dialog should appear with create form.
    expect(find.text('قالب فاتورة متكررة'), findsOneWidget);
    expect(find.text('اسم القالب (مثل: إيجار المحل)'), findsOneWidget);
  });

  testWidgets('tapping process button shows result SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RecurringInvoicesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('توليد الفواتير المستحقة'));
    await tester.pumpAndSettle();

    // Should show a SnackBar with the result.
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

// ── Mocks ────────────────────────────────────────────────────────────

class _MockDatabaseHelper implements DatabaseHelper {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockInvoiceRepository implements InvoiceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockReferenceDataRepository implements ReferenceDataRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockRecurringInvoiceService implements RecurringInvoiceService {
  @override
  Future<List<Map<String, dynamic>>> getAllTemplates({String? status}) async {
    return []; // Empty — triggers empty state.
  }

  @override
  Future<RecurringGenerationResult> processDueTemplates() async {
    return const RecurringGenerationResult(
      generated: 0,
      skipped: 0,
      failed: 0,
      errors: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
