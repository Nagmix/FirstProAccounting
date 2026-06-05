import 'package:flutter/foundation.dart';

import 'license_models.dart';
import 'license_service.dart';

/// ChangeNotifier provider for license state.
/// Used to notify the UI when the license state changes.
class LicenseProvider extends ChangeNotifier {
  LicenseProvider() {
    _loadState();
  }

  LicenseStateModel _state = const LicenseStateModel();
  LicenseStateModel get state => _state;

  bool _loading = false;
  bool get loading => _loading;

  String? _activationError;
  String? get activationError => _activationError;

  void _loadState() {
    _state = LicenseService.instance.state;
  }

  /// Initialize the license service and update state.
  Future<void> initialize() async {
    _loading = true;
    notifyListeners();

    try {
      await LicenseService.instance.initialize();
      _state = LicenseService.instance.state;
    } catch (e) {
      if (kDebugMode) debugPrint('LicenseProvider init error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Activate a license key.
  Future<bool> activate(String licenseKey) async {
    _loading = true;
    _activationError = null;
    notifyListeners();

    try {
      final success = await LicenseService.instance.activate(licenseKey);
      _state = LicenseService.instance.state;

      if (!success) {
        _activationError = 'فشل تفعيل المفتاح. تأكد من صحة المفتاح وحاول مرة أخرى';
      }

      return success;
    } catch (e) {
      _activationError = 'حدث خطأ أثناء التفعيل';
      if (kDebugMode) debugPrint('Activation error: $e');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Check if a record can be added.
  Future<bool> canAddRecord() async {
    return LicenseService.instance.canAddRecord();
  }

  /// Refresh the license state (re-validate with server).
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();

    try {
      await LicenseService.instance.syncWithServer();
      _state = LicenseService.instance.state;
    } catch (e) {
      if (kDebugMode) debugPrint('Refresh error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Whether the current edition is free.
  bool get isFree => _state.isFree;

  /// Whether the current edition is premium.
  bool get isPremium => _state.isPremium;

  /// Whether ads should be shown.
  bool get shouldShowAds => _state.isFree;

  /// Number of remaining records in the free edition.
  int get remainingRecords => LicenseService.instance.getRemainingRecords();

  /// Get the device fingerprint for sharing via WhatsApp.
  String get deviceFingerprint => _state.deviceFingerprint ?? '';
}
