import 'dart:async';

import 'package:firstpro/data/models/business_profile_model.dart';

/// Runs non-critical local jobs only after first-run setup is complete.
///
/// Keeping this gate outside the app widget makes the startup invariant
/// deterministic and prevents background work from touching partially
/// initialized reference data.
class StartupBackgroundJobRunner {
  final Future<BusinessProfile> Function() loadProfile;
  final Future<bool> Function() isReferenceDataReady;
  final Future<void> Function() inventoryScan;
  final Future<void> Function() recurringProcessing;

  const StartupBackgroundJobRunner({
    required this.loadProfile,
    required this.isReferenceDataReady,
    required this.inventoryScan,
    required this.recurringProcessing,
  });

  /// Starts both jobs in the background when all startup prerequisites pass.
  /// Returns false when the jobs were intentionally skipped.
  Future<bool> runIfReady() async {
    try {
      final profile = await loadProfile();
      if (profile.setupStatus != 'completed') return false;
      if (!await isReferenceDataReady()) return false;

      unawaited(_runSafely(inventoryScan));
      unawaited(_runSafely(recurringProcessing));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runSafely(Future<void> Function() job) async {
    try {
      await job();
    } catch (_) {
      // Background alerts/invoice generation must not block app startup.
    }
  }
}
