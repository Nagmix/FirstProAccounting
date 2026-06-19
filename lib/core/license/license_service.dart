import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/core/license/device_fingerprint.dart';
import 'package:firstpro/core/license/license_api_client.dart';
import 'package:firstpro/core/license/license_constants.dart';
import 'package:firstpro/core/license/license_models.dart';

/// Main service for managing the application license.
/// Handles activation, validation, offline grace periods, and feature gating.
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  LicenseStateModel _state = const LicenseStateModel();
  LicenseStateModel get state => _state;

  /// Whether the service has been initialized.
  bool _initialized = false;
  bool get initialized => _initialized;

  /// Initialize the license service.
  /// Loads state from local database and secure storage.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize API client
      LicenseApiClient.instance.init();

      // Get or create installation ID
      final installationId =
          await DeviceFingerprint.instance.getInstallationId();

      // Get device fingerprint
      final deviceFingerprint = await DeviceFingerprint.instance.generate();

      // Load state from local database
      final db = await DatabaseHelper().database;
      final results = await db.query(
        'license_state',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (results.isNotEmpty) {
        _state = LicenseStateModel.fromMap(results.first);
      } else {
        // First run — create default state
        _state = LicenseStateModel(
          status: LicenseStatus.free,
          licenseType: LicenseType.free,
          installationId: installationId,
          deviceFingerprint: deviceFingerprint,
          serverUrl: LicenseConstants.apiBaseUrl,
          lastValidatedAt: DateTime.now(),
        );
        await _saveState();
      }

      // Update device fingerprint if it changed (hardware change detection)
      if (_state.deviceFingerprint != deviceFingerprint) {
        _state = _state.copyWith(deviceFingerprint: deviceFingerprint);
        await _saveState();
      }

      // Update installation ID if it changed
      if (_state.installationId != installationId) {
        _state = _state.copyWith(installationId: installationId);
        await _saveState();
      }

      // Try to validate with server if we have internet
      await _tryServerValidation();

      _initialized = true;
      if (kDebugMode) {
        debugPrint('LicenseService initialized: status=${_state.status.value}, '
            'type=${_state.licenseType.value}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LicenseService init error: $e');
      // Fallback to free mode on error
      _state = const LicenseStateModel(
        status: LicenseStatus.free,
        licenseType: LicenseType.free,
      );
      _initialized = true;
    }
  }

  /// Try to validate the license with the server.
  Future<void> _tryServerValidation() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet =
          connectivityResult.any((r) => r != ConnectivityResult.none);

      if (!hasInternet) {
        // No internet — check offline grace period
        await _handleOfflineMode();
        return;
      }

      // If we have a license key, validate it
      if (_state.licenseKey != null && _state.licenseKey!.isNotEmpty) {
        final result = await LicenseApiClient.instance.validate(
          licenseKey: _state.licenseKey!,
          deviceFingerprint: _state.deviceFingerprint ?? '',
          installationId: _state.installationId ?? '',
          recordCount: _state.recordCount,
        );

        if (result['success'] == true) {
          _state = _state.copyWith(
            status: LicenseStatus.active,
            licenseType: LicenseType.fromString(
                result['license_type'] as String? ?? 'monthly'),
            expiresAt: result['expires_at'] != null
                ? DateTime.tryParse(result['expires_at'] as String)
                : null,
            lastValidatedAt: DateTime.now(),
            lastSyncAt: DateTime.now(),
            isOfflineGrace: false,
            offlineSince: null,
          );
        } else {
          final error = result['error'] as String?;
          if (error == 'LICENSE_EXPIRED') {
            _state = _state.copyWith(status: LicenseStatus.expired);
          } else if (error == 'LICENSE_REVOKED') {
            _state = _state.copyWith(status: LicenseStatus.revoked);
          } else if (error == 'DEVICE_NOT_AUTHORIZED') {
            // Device is no longer authorized — revert to free
            _state = _state.copyWith(
              status: LicenseStatus.free,
              licenseType: LicenseType.free,
            );
          }
          // For other errors (NETWORK_ERROR etc.), keep current state
        }
      }

      await _saveState();
    } catch (e) {
      if (kDebugMode) debugPrint('Server validation error: $e');
      await _handleOfflineMode();
    }
  }

  /// Handle offline mode — check grace period.
  Future<void> _handleOfflineMode() async {
    if (_state.isPremium) {
      if (!_state.isOfflineGrace) {
        // Start grace period
        _state = _state.copyWith(
          isOfflineGrace: true,
          offlineSince: DateTime.now(),
        );
      } else if (!_state.canUseOffline) {
        // Grace period expired — downgrade to restricted
        if (kDebugMode) {
          debugPrint('Offline grace period expired');
        }
        // Don't revoke — just mark as needing connection
      }
    }
    await _saveState();
  }

  /// Activate a license key.
  Future<bool> activate(String licenseKey) async {
    try {
      final deviceFingerprint = _state.deviceFingerprint ??
          await DeviceFingerprint.instance.generate();
      final installationId = _state.installationId ??
          await DeviceFingerprint.instance.getInstallationId();
      final deviceInfo = await DeviceFingerprint.instance.getDeviceInfo();

      final result = await LicenseApiClient.instance.activate(
        licenseKey: licenseKey,
        deviceFingerprint: deviceFingerprint,
        installationId: installationId,
        appVersion: deviceInfo['app_version'],
        osVersion: deviceInfo['os_version'],
        deviceModel: deviceInfo['device_model'],
      );

      if (result['success'] == true) {
        // Store session token securely
        final sessionToken = result['session_token'] as String?;
        if (sessionToken != null) {
          await _secureStorage.write(
            key: LicenseConstants.sessionTokenKey,
            value: sessionToken,
          );
        }

        // Update state
        _state = _state.copyWith(
          licenseKey: licenseKey,
          status: LicenseStatus.active,
          licenseType: LicenseType.fromString(
            result['license_type'] as String? ?? 'monthly',
          ),
          expiresAt: result['expires_at'] != null
              ? DateTime.tryParse(result['expires_at'] as String)
              : null,
          lastValidatedAt: DateTime.now(),
          lastSyncAt: DateTime.now(),
          isOfflineGrace: false,
          offlineSince: null,
        );

        await _saveState();

        // Also store key in secure storage
        await _secureStorage.write(
          key: LicenseConstants.licenseKeyStorage,
          value: licenseKey,
        );
        await _secureStorage.write(
          key: LicenseConstants.licenseStatusKey,
          value: 'active',
        );

        return true;
      }

      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('Activation error: $e');
      return false;
    }
  }

  /// Check if the user can add a new record.
  /// Returns true if allowed, false if the record limit is reached.
  Future<bool> canAddRecord() async {
    if (_state.isPremium) return true;

    final count = await _getTotalRecordCount();
    return count < LicenseConstants.freeRecordLimit;
  }

  /// Get the total record count across all major tables.
  Future<int> _getTotalRecordCount() async {
    try {
      final db = await DatabaseHelper().database;

      final tables = ['products', 'customers', 'invoices', 'expenses'];
      int total = 0;

      for (final table in tables) {
        final result =
            await db.rawQuery('SELECT COUNT(*) as count FROM $table');
        total += Sqflite.firstIntValue(result) ?? 0;
      }

      // Update state
      _state = _state.copyWith(recordCount: total);
      await _saveState();

      return total;
    } catch (e) {
      if (kDebugMode) debugPrint('Error counting records: $e');
      return _state.recordCount;
    }
  }

  /// Get the number of remaining records in the free edition.
  int getRemainingRecords() {
    if (_state.isPremium) return -1; // Unlimited
    final remaining = LicenseConstants.freeRecordLimit - _state.recordCount;
    return remaining > 0 ? remaining : 0;
  }

  /// Whether the app should show ads (free edition only).
  bool get shouldShowAds => _state.isFree;

  /// Whether premium features are available.
  bool get hasPremiumFeatures => _state.isPremium;

  /// Sync usage data with the server.
  Future<void> syncWithServer() async {
    if (_state.licenseKey == null || _state.licenseKey!.isEmpty) return;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet =
          connectivityResult.any((r) => r != ConnectivityResult.none);
      if (!hasInternet) return;

      final count = await _getTotalRecordCount();
      await LicenseApiClient.instance.reportUsage(
        installationId: _state.installationId ?? '',
        recordCount: count,
      );

      _state = _state.copyWith(lastSyncAt: DateTime.now());
      await _saveState();
    } catch (e) {
      if (kDebugMode) debugPrint('Sync error: $e');
    }
  }

  /// Save current state to local database.
  ///
  /// T-01 fix (2026-06-19): the previous implementation used
  /// `DELETE FROM license_state` followed by `INSERT`. If the INSERT
  /// failed (e.g. constraint violation, disk error, process kill
  /// between the two statements), the user's license state was lost
  /// — including the license key itself — causing the app to silently
  /// revert to 'free' mode on the next launch.
  ///
  /// The new implementation uses `INSERT OR REPLACE` (SQLite UPSERT)
  /// which atomically replaces the single row (id=1, enforced by the
  /// table's `PRIMARY KEY CHECK (id = 1)` constraint) in one
  /// statement. There is no window where the row is missing.
  ///
  /// The map from `_state.toMap()` already includes `id: 1` (set in
  /// `LicenseStateModel.toMap`), so INSERT OR REPLACE will target
  /// the existing row correctly.
  Future<void> _saveState() async {
    try {
      final db = await DatabaseHelper().database;
      final map = _state.toMap();
      // Ensure the row id is 1 (the table's CHECK constraint requires
      // it). toMap() should already set this, but we enforce it here
      // defensively in case the model changes.
      map['id'] = 1;
      await db.insert(
        'license_state',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Save license state error: $e');
    }
  }

  /// Check if validation is needed (has it been more than 24 hours?).
  bool get needsValidation {
    if (_state.lastValidatedAt == null) return true;
    final elapsed = DateTime.now().difference(_state.lastValidatedAt!);
    return elapsed.inHours >= LicenseConstants.validationIntervalHours;
  }

  /// Get an error message in Arabic for a given error code.
  static String getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'LICENSE_NOT_FOUND':
        return 'مفتاح الترخيص غير صحيح';
      case 'LICENSE_EXPIRED':
        return 'انتهت صلاحية الترخيص';
      case 'LICENSE_REVOKED':
        return 'تم إلغاء الترخيص';
      case 'MAX_DEVICES_EXCEEDED':
        return 'تم تجاوز الحد الأقصى للأجهزة المرتبطة بهذا الترخيص';
      case 'DEVICE_BLOCKED':
        return 'تم حظر هذا الجهاز';
      case 'DEVICE_NOT_AUTHORIZED':
        return 'هذا الجهاز غير مصرح له باستخدام هذا الترخيص';
      case 'NETWORK_ERROR':
        return 'فشل الاتصال بالخادم. تحقق من اتصال الإنترنت';
      case 'LICENSE_ALREADY_ACTIVE_ON_ANOTHER_DEVICE':
        return 'هذا الترخيص مفعل على جهاز آخر بالفعل';
      default:
        return 'حدث خطأ غير متوقع. حاول مرة أخرى';
    }
  }
}
