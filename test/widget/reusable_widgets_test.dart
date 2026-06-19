import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/ui/widgets/stat_card.dart';
import 'package:firstpro/ui/widgets/empty_state.dart';
import 'package:firstpro/ui/widgets/quick_action_button.dart';
import 'package:firstpro/ui/widgets/transaction_tile.dart';

/// P-01: Widget tests for reusable UI components.
///
/// These tests verify that the reusable widgets (StatCard, EmptyState,
/// QuickActionButton, TransactionTile) render correctly with various
/// inputs and respond to user interactions. They don't require DB or
/// DI setup — just MaterialApp wrapping.
void main() {
  group('StatCard', () {
    testWidgets('renders title and value correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: 'مبيعات اليوم',
              value: 1234.56,
              icon: Icons.trending_up,
              color: Colors.green,
            ),
          ),
        ),
      );

      expect(find.text('مبيعات اليوم'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: 'الفواتير',
              value: 42,
              icon: Icons.receipt,
              color: Colors.blue,
              subtitle: 'اليوم',
            ),
          ),
        ),
      );

      expect(find.text('الفواتير'), findsOneWidget);
      expect(find.text('اليوم'), findsOneWidget);
    });

    testWidgets('renders trend percentage when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: 'المبيعات',
              value: 5000,
              icon: Icons.trending_up,
              color: Colors.green,
              trendPercentage: 15.5,
            ),
          ),
        ),
      );

      expect(find.text('المبيعات'), findsOneWidget);
    });

    testWidgets('renders as count (integer) when isCount is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: 'المنتجات',
              value: 25,
              icon: Icons.inventory,
              color: Colors.orange,
              isCount: true,
            ),
          ),
        ),
      );

      expect(find.text('المنتجات'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox,
              title: 'لا توجد بيانات',
              subtitle: 'ابدأ بإضافة عنصر جديد',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('لا توجد بيانات'), findsOneWidget);
      expect(find.text('ابدأ بإضافة عنصر جديد'), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      var actionPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.add_circle,
              title: 'لا توجد فواتير',
              subtitle: 'لم يتم إنشاء أي فاتورة بعد',
              actionLabel: 'إنشاء فاتورة',
              onAction: () => actionPressed = true,
            ),
          ),
        ),
      );

      expect(find.text('إنشاء فاتورة'), findsOneWidget);
      await tester.tap(find.text('إنشاء فاتورة'));
      expect(actionPressed, isTrue);
    });

    testWidgets('does not render action button when not provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.search,
              title: 'لا نتائج',
              subtitle: 'جرب كلمات بحث أخرى',
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('QuickActionButton', () {
    testWidgets('renders label and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickActionButton(
              label: 'فاتورة جديدة',
              icon: Icons.add,
              color: Colors.blue,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('فاتورة جديدة'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickActionButton(
              label: 'عملاء',
              icon: Icons.people,
              color: Colors.green,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(QuickActionButton));
      expect(tapped, isTrue);
    });

    testWidgets('renders large variant correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickActionButton(
              label: 'POS',
              icon: Icons.point_of_sale,
              color: Colors.purple,
              isLarge: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('POS'), findsOneWidget);
      expect(find.byIcon(Icons.point_of_sale), findsOneWidget);
    });
  });

  group('TransactionTile', () {
    testWidgets('renders customer name, amount, and date', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              customerName: 'أحمد محمد',
              amount: 1500.00,
              date: DateTime(2026, 6, 15),
              status: TransactionStatus.paid,
            ),
          ),
        ),
      );

      expect(find.text('أحمد محمد'), findsOneWidget);
    });

    testWidgets('shows correct status indicator for paid', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              customerName: 'عميل مدفوع',
              amount: 500.00,
              date: DateTime(2026, 6, 10),
              status: TransactionStatus.paid,
            ),
          ),
        ),
      );

      expect(find.text('عميل مدفوع'), findsOneWidget);
    });

    testWidgets('shows correct status indicator for unpaid', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              customerName: 'عميل غير مدفوع',
              amount: 800.00,
              date: DateTime(2026, 6, 12),
              status: TransactionStatus.unpaid,
            ),
          ),
        ),
      );

      expect(find.text('عميل غير مدفوع'), findsOneWidget);
    });

    testWidgets('shows correct status indicator for pending', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              customerName: 'عميل معلق',
              amount: 300.00,
              date: DateTime(2026, 6, 14),
              status: TransactionStatus.pending,
            ),
          ),
        ),
      );

      expect(find.text('عميل معلق'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              customerName: 'عميل',
              amount: 100.00,
              date: DateTime(2026, 6, 1),
              status: TransactionStatus.paid,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TransactionTile));
      expect(tapped, isTrue);
    });
  });
}
