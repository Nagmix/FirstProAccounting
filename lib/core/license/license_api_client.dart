import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:firstpro/core/license/license_constants.dart';

/// API client for communicating with the license server.
class LicenseApiClient {
  LicenseApiClient._();
  static final LicenseApiClient instance = LicenseApiClient._();

  late final Dio _dio;

  /// Initialize the Dio client with base options.
  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: LicenseConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add safe metadata-only logging in debug mode. Never log request or
    // response bodies because they may contain license_key, device_fingerprint,
    // or session_token values.
    if (kDebugMode) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('License API request: ${options.method} ${options.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            'License API response: ${response.requestOptions.path} status=${response.statusCode}',
          );
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint(
            'License API error: ${error.requestOptions.path} ${error.type}',
          );
          handler.next(error);
        },
      ));
    }
  }

  /// Activate a license key on the server.
  Future<Map<String, dynamic>> activate({
    required String licenseKey,
    required String deviceFingerprint,
    required String installationId,
    String? appVersion,
    String? osVersion,
    String? deviceModel,
  }) async {
    try {
      final response = await _dio.post(
        LicenseConstants.activateEndpoint,
        data: {
          'license_key': licenseKey,
          'device_fingerprint': deviceFingerprint,
          'installation_id': installationId,
          if (appVersion != null) 'app_version': appVersion,
          if (osVersion != null) 'os_version': osVersion,
          if (deviceModel != null) 'device_model': deviceModel,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('Activate API error: ${e.message}');
      if (e.response?.data != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'NETWORK_ERROR'};
    } catch (e) {
      if (kDebugMode) debugPrint('Activate error: $e');
      return {'success': false, 'error': 'UNKNOWN_ERROR'};
    }
  }

  /// Validate the current license with the server.
  Future<Map<String, dynamic>> validate({
    required String licenseKey,
    required String deviceFingerprint,
    required String installationId,
    int? recordCount,
  }) async {
    try {
      final response = await _dio.post(
        LicenseConstants.validateEndpoint,
        data: {
          'license_key': licenseKey,
          'device_fingerprint': deviceFingerprint,
          'installation_id': installationId,
          if (recordCount != null) 'record_count': recordCount,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('Validate API error: ${e.message}');
      if (e.response?.data != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'NETWORK_ERROR'};
    } catch (e) {
      if (kDebugMode) debugPrint('Validate error: $e');
      return {'success': false, 'error': 'UNKNOWN_ERROR'};
    }
  }

  /// Rebind the license to a new device fingerprint.
  Future<Map<String, dynamic>> rebind({
    required String licenseKey,
    required String oldDeviceFingerprint,
    required String newDeviceFingerprint,
    required String installationId,
  }) async {
    try {
      final response = await _dio.post(
        LicenseConstants.rebindEndpoint,
        data: {
          'license_key': licenseKey,
          'old_device_fingerprint': oldDeviceFingerprint,
          'new_device_fingerprint': newDeviceFingerprint,
          'installation_id': installationId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('Rebind API error: ${e.message}');
      if (e.response?.data != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'NETWORK_ERROR'};
    } catch (e) {
      if (kDebugMode) debugPrint('Rebind error: $e');
      return {'success': false, 'error': 'UNKNOWN_ERROR'};
    }
  }

  /// Report usage (record count) to the server.
  Future<Map<String, dynamic>> reportUsage({
    required String installationId,
    required int recordCount,
  }) async {
    try {
      final response = await _dio.post(
        LicenseConstants.usageEndpoint,
        data: {
          'installation_id': installationId,
          'record_count': recordCount,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('Usage API error: ${e.message}');
      return {'success': false, 'error': 'NETWORK_ERROR'};
    } catch (e) {
      if (kDebugMode) debugPrint('Usage error: $e');
      return {'success': false, 'error': 'UNKNOWN_ERROR'};
    }
  }

  /// Get the license status from the server.
  Future<Map<String, dynamic>> getStatus(String licenseKey) async {
    try {
      final response = await _dio.get(
        LicenseConstants.statusEndpoint,
        queryParameters: {'license_key': licenseKey},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('Status API error: ${e.message}');
      return {'success': false, 'error': 'NETWORK_ERROR'};
    } catch (e) {
      if (kDebugMode) debugPrint('Status error: $e');
      return {'success': false, 'error': 'UNKNOWN_ERROR'};
    }
  }
}
