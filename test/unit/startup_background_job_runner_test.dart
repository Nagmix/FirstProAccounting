import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/business_profile_model.dart';
import 'package:firstpro/core/platform/startup_background_job_runner.dart';

void main() {
  test('startup jobs stay disabled until setup is completed', () async {
    var inventoryRuns = 0;
    var recurringRuns = 0;
    final runner = StartupBackgroundJobRunner(
      loadProfile: () async => _profile(setupStatus: 'not_started'),
      isReferenceDataReady: () async => true,
      inventoryScan: () async => inventoryRuns++,
      recurringProcessing: () async => recurringRuns++,
    );

    expect(await runner.runIfReady(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(inventoryRuns, 0);
    expect(recurringRuns, 0);
  });

  test('startup jobs stay disabled when reference data is unavailable', () async {
    var inventoryRuns = 0;
    var recurringRuns = 0;
    final runner = StartupBackgroundJobRunner(
      loadProfile: () async => _profile(setupStatus: 'completed'),
      isReferenceDataReady: () async => false,
      inventoryScan: () async => inventoryRuns++,
      recurringProcessing: () async => recurringRuns++,
    );

    expect(await runner.runIfReady(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(inventoryRuns, 0);
    expect(recurringRuns, 0);
  });

  test('startup jobs run only after setup and reference data are ready', () async {
    var inventoryRuns = 0;
    var recurringRuns = 0;
    final runner = StartupBackgroundJobRunner(
      loadProfile: () async => _profile(setupStatus: 'completed'),
      isReferenceDataReady: () async => true,
      inventoryScan: () async => inventoryRuns++,
      recurringProcessing: () async => recurringRuns++,
    );

    expect(await runner.runIfReady(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(inventoryRuns, 1);
    expect(recurringRuns, 1);
  });
}

BusinessProfile _profile({required String setupStatus}) => BusinessProfile(
      businessName: 'متجر الاختبار',
      phone: null,
      email: null,
      address: null,
      logoPath: null,
      countryCode: 'YE',
      baseCurrencyCode: 'YER',
      locale: 'ar',
      timezone: 'Asia/Aden',
      taxMode: 'none',
      setupStatus: setupStatus,
      setupVersion: 1,
      source: 'test',
    );
