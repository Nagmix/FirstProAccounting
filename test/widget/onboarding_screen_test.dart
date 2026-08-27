import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/onboarding_viewmodel.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/business_profile_repository.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:firstpro/data/models/business_profile_model.dart';
import 'package:firstpro/ui/screens/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('onboarding presents simple multi-capability setup and completes',
      (tester) async {
    final profileRepository = _FakeBusinessProfileRepository(
      profile: _migrationProfile(),
    );
    final capabilityRepository = _FakeCapabilityRepository();
    final viewModel = OnboardingViewModel(
      profileRepository: profileRepository,
      capabilityRepository: capabilityRepository,
    );
    var completed = false;

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

    expect(find.text('لنبدأ بإعداد برنامجك'), findsOneWidget);
    expect(find.text('ما الذي تريد إدارته؟'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('البيع'), findsOneWidget);
    expect(find.text('الخدمات أو الطلبات'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'متجر البداية');
    await tester.tap(find.byType(CheckboxListTile).at(0));
    final serviceTile = find.byType(CheckboxListTile).at(3);
    await tester.ensureVisible(serviceTile);
    await tester.tap(serviceTile);
    await tester.pump();

    expect(find.text('متابعة'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'متابعة'),
          )
          .onPressed,
      isNotNull,
    );

    final continueButton = find.widgetWithText(ElevatedButton, 'متابعة');
    await tester.scrollUntilVisible(
      continueButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<ElevatedButton>(continueButton).onPressed!();
    await tester.pump();

    expect(completed, isTrue);
    expect(profileRepository.savedProfile?.businessName, 'متجر البداية');
    expect(profileRepository.savedProfile?.setupStatus, 'completed');
    expect(capabilityRepository.savedCodes, contains('sell'));
    expect(capabilityRepository.savedCodes, contains('service'));
  });

  testWidgets('onboarding guides trader through preferences before review',
      (tester) async {
    final profileRepository = _FakeBusinessProfileRepository(
      profile: _migrationProfile(),
    );
    final viewModel = OnboardingViewModel(
      profileRepository: profileRepository,
      capabilityRepository: _FakeCapabilityRepository(),
    );

    await viewModel.load();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          viewModel: viewModel,
          loadOnInit: false,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'متجر البداية');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('الخطوة 1 من 4'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'التالي'));
    await tester.pump();
    expect(find.text('البلد والعملة'), findsOneWidget);
    expect(find.text('اليمن'), findsOneWidget);
    expect(find.text('الريال اليمني'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'التالي'));
    await tester.pump();
    expect(find.text('طريقة الضريبة'), findsOneWidget);
    expect(find.text('بدون ضريبة'), findsOneWidget);
    expect(find.text('ضريبة قياسية'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'التالي'));
    await tester.pump();
    expect(find.text('مراجعة الإعدادات'), findsOneWidget);
    expect(find.text('متجر البداية'), findsOneWidget);
    expect(find.text('YER'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'حفظ وبدء الاستخدام'),
        findsOneWidget);
  });

  testWidgets('onboarding shows retry state when loading fails', (tester) async {
    final viewModel = OnboardingViewModel(
      profileRepository: _FakeBusinessProfileRepository(
        profile: _migrationProfile(),
        failOnLoad: true,
      ),
      capabilityRepository: _FakeCapabilityRepository(),
    );

    await viewModel.load();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(viewModel: viewModel, loadOnInit: false),
      ),
    );
    await tester.pump();

    expect(find.text('تعذر تحميل إعدادات البداية. حاول مرة أخرى.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}

BusinessProfile _migrationProfile() => const BusinessProfile(
      businessName: null,
      phone: null,
      email: null,
      address: null,
      logoPath: null,
      countryCode: 'YE',
      baseCurrencyCode: 'YER',
      locale: 'ar',
      timezone: 'Asia/Aden',
      taxMode: 'none',
      setupStatus: 'not_started',
      setupVersion: 1,
      source: 'migration',
    );

class _FakeBusinessProfileRepository extends BusinessProfileRepository {
  final BusinessProfile profile;
  final bool failOnLoad;
  BusinessProfile? savedProfile;

  _FakeBusinessProfileRepository({required this.profile, this.failOnLoad = false})
      : super(DatabaseHelper());

  @override
  Future<BusinessProfile> getOrCreateProfile() async {
    if (failOnLoad) throw StateError('controlled load failure');
    return profile;
  }

  @override
  Future<void> saveProfile(BusinessProfile value) async {
    savedProfile = value;
  }
}

class _FakeCapabilityRepository extends CapabilityRepository {
  Set<String> savedCodes = <String>{};

  _FakeCapabilityRepository() : super(DatabaseHelper());

  @override
  Future<Set<String>> getEnabledCodes() async => <String>{};

  @override
  Future<void> replaceEnabledCodes(
    Iterable<String> requested, {
    required String source,
  }) async {
    savedCodes = requested.toSet();
  }
}
