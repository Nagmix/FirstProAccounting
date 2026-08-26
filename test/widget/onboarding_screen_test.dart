import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/onboarding_viewmodel.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/business_profile_repository.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:firstpro/ui/screens/onboarding/onboarding_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(Database, OnboardingViewModel)> createViewModel() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    return (
      db,
      OnboardingViewModel(
        profileRepository: BusinessProfileRepository(DatabaseHelper()),
        capabilityRepository: CapabilityRepository(DatabaseHelper()),
      ),
    );
  }

  tearDown(() {
    DatabaseHelper.clearTestDatabase();
  });

  testWidgets('onboarding presents simple multi-capability setup and completes',
      (tester) async {
    final (db, viewModel) = await createViewModel();
    var completed = false;
    try {
      await viewModel.load();
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            viewModel: viewModel,
            loadOnInit: false,
            onCompleted: () => completed = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('لنبدأ بإعداد برنامجك'), findsOneWidget);
      expect(find.text('ما الذي تريد إدارته؟'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('البيع'), findsOneWidget);
      expect(find.text('الخدمات أو الطلبات'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'متجر البداية');
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.tap(find.byType(CheckboxListTile).at(3));
      await tester.pump();

      expect(find.text('متابعة'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'متابعة')).onPressed,
          isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'متابعة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(completed, isTrue);
      expect(await db.query('business_profile'), hasLength(1));
    } finally {
      await db.close();
    }
  });

  testWidgets('onboarding shows retry state when loading fails', (tester) async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
    );
    await db.close();
    DatabaseHelper.useTestDatabase(db);
    final viewModel = OnboardingViewModel(
      profileRepository: BusinessProfileRepository(DatabaseHelper()),
      capabilityRepository: CapabilityRepository(DatabaseHelper()),
    );
    await viewModel.load();

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(viewModel: viewModel, loadOnInit: false),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تعذر تحميل إعدادات البداية. حاول مرة أخرى.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}
