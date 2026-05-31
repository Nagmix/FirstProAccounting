import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/datasources/repositories/reference_data_repository.dart';
import 'settings_helpers.dart';

/// App lock section: PIN toggle, set/change PIN, and biometric authentication.
///
/// This is a [StatefulWidget] because it manages PIN hashing salt and the
/// PIN dialog internally. The parent passes current lock state values and
/// callbacks for persisting changes.
class SettingsAppLockSection extends StatefulWidget {
  final bool isDark;
  final Future<void> Function(String key, String value) saveSetting;

  /// Whether PIN lock is currently enabled.
  final bool pinEnabled;

  /// Whether biometric auth is currently enabled.
  final bool biometricEnabled;

  /// Whether the device supports biometric authentication.
  final bool isBiometricAvailable;

  /// Callback invoked when the PIN enabled state changes.
  final ValueChanged<bool> onPinEnabledChanged;

  /// Callback invoked when the biometric enabled state changes.
  final ValueChanged<bool> onBiometricEnabledChanged;

  const SettingsAppLockSection({
    super.key,
    required this.isDark,
    required this.saveSetting,
    required this.pinEnabled,
    required this.biometricEnabled,
    required this.isBiometricAvailable,
    required this.onPinEnabledChanged,
    required this.onBiometricEnabledChanged,
  });

  @override
  State<SettingsAppLockSection> createState() => _SettingsAppLockSectionState();
}

class _SettingsAppLockSectionState extends State<SettingsAppLockSection> {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Secure SHA-256 based PIN hashing with per-installation salt (C-04).
  /// New format uses 'h3$' prefix; must match app_lock_screen.dart.
  String? _pinSalt;

  @override
  void initState() {
    super.initState();
    _loadPinSalt();
  }

  Future<void> _loadPinSalt() async {
    final salt = await _getOrCreatePinSalt();
    if (mounted) {
      setState(() => _pinSalt = salt);
    }
  }

  Future<String> _getOrCreatePinSalt() async {
    try {
      const storage = FlutterSecureStorage();
      var salt = await storage.read(key: 'pin_salt');
      if (salt == null || salt.isEmpty) {
        final random = DateTime.now().microsecondsSinceEpoch.toString() +
            DateTime.now().millisecond.toString();
        final saltBytes = sha256.convert(utf8.encode(random)).bytes;
        salt = base64Encode(saltBytes);
        await storage.write(key: 'pin_salt', value: salt);
      }
      return salt;
    } catch (_) {
      return 'F1r5tPr0_Fallback_2024_Salt';
    }
  }

  String _hashPin(String pin) {
    final salt = _pinSalt ?? 'F1r5tPr0_Fallback_2024_Salt';
    final key = utf8.encode('$salt$pin$salt');
    final bytes = sha256.convert(key).bytes;
    var currentBytes = bytes;
    for (var round = 0; round < 1000; round++) {
      final roundKey = utf8.encode('$salt${base64Encode(currentBytes)}$pin$round');
      currentBytes = sha256.convert(roundKey).bytes;
    }
    return 'h3\$${base64Encode(currentBytes)}';
  }

  // ════════════════════════════════════════════════════════════════
  //  PIN DIALOG
  // ════════════════════════════════════════════════════════════════

  /// Shows a dialog for entering a 4-digit PIN.
  /// Returns the entered PIN string if confirmed, or null if cancelled.
  Future<String?> _showPinDialog({required bool isSetting}) async {
    String pin = '';
    String confirmPin = '';
    bool isConfirming = false;
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void onDigit(String digit) {
              if (isConfirming && confirmPin.length >= 4) return;
              if (!isConfirming && pin.length >= 4) return;

              setDialogState(() {
                if (isConfirming) {
                  confirmPin += digit;
                } else {
                  pin += digit;
                }
                errorText = null;
              });

              // Auto-advance to confirm step
              if (!isConfirming && pin.length == 4) {
                setDialogState(() {
                  isConfirming = true;
                });
              }

              // Auto-confirm when confirmation PIN is complete
              if (isConfirming && confirmPin.length == 4) {
                if (pin == confirmPin) {
                  Navigator.pop(ctx, pin);
                } else {
                  setDialogState(() {
                    errorText = 'رمز PIN غير متطابق، حاول مرة أخرى';
                    confirmPin = '';
                    isConfirming = true;
                    pin = '';
                    isConfirming = false;
                  });
                }
              }
            }

            void onBackspace() {
              setDialogState(() {
                if (isConfirming && confirmPin.isNotEmpty) {
                  confirmPin = confirmPin.substring(0, confirmPin.length - 1);
                } else if (!isConfirming && pin.isNotEmpty) {
                  pin = pin.substring(0, pin.length - 1);
                }
                errorText = null;
              });
            }

            final currentPin = isConfirming ? confirmPin : pin;
            final title = isConfirming ? 'أعد إدخال رمز PIN' : 'أدخل رمز PIN الجديد';

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PIN dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < currentPin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: errorText != null
                                ? AppColors.error
                                : isFilled
                                    ? AppColors.primary
                                    : Colors.grey[400]!,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  const SizedBox(height: 12),
                  // Numeric keypad
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var d = 1; d <= 9; d++)
                        SizedBox(
                          width: 64,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => onDigit(d.toString()),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              d.toString(),
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 64,
                        height: 48,
                        child: IconButton(
                          onPressed: onBackspace,
                          icon: const Icon(Icons.backspace),
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => onDigit('0'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('0', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      SizedBox(width: 64, height: 48), // spacer
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: 'قفل التطبيق',
      icon: Icons.lock,
      isDark: widget.isDark,
      children: [
        SwitchListTile(
          secondary: Icon(
            Icons.lock,
            color: widget.pinEnabled ? AppColors.primary : null,
          ),
          title: const Text('تفعيل قفل PIN'),
          subtitle: const Text('طلب رمز PIN عند فتح التطبيق'),
          value: widget.pinEnabled,
          activeColor: AppColors.primary,
          onChanged: (v) async {
            if (v) {
              // Enabling PIN — must set a PIN first
              final pin = await _showPinDialog(isSetting: true);
              if (pin != null && pin.length == 4) {
                await _secureStorage.write(key: 'pin_enabled', value: '1');
                await _secureStorage.write(key: 'app_pin', value: _hashPin(pin));
                // Clean up old DB entries if they exist
                try {
                  final refRepo = locator<ReferenceDataRepository>();
                  await refRepo.deleteSetting('pin_enabled');
                  await refRepo.deleteSetting('app_pin');
                } catch (_) {}
                widget.onPinEnabledChanged(true);
              }
            } else {
              // Disabling PIN — delete from secure storage
              await _secureStorage.delete(key: 'pin_enabled');
              widget.onPinEnabledChanged(false);
              widget.onBiometricEnabledChanged(false);
              await widget.saveSetting('biometric_enabled', '0');
            }
          },
        ),
        ActionTile(
          icon: Icons.key,
          title: widget.pinEnabled ? 'تغيير رمز PIN' : 'تعيين رمز PIN',
          subtitle: widget.pinEnabled
              ? 'تعديل رمز القفل المكون من 4 أرقام'
              : 'تعيين رمز PIN من 4 أرقام لحماية التطبيق',
          onTap: () async {
            final pin = await _showPinDialog(isSetting: true);
            if (pin != null && pin.length == 4) {
              await _secureStorage.write(key: 'app_pin', value: _hashPin(pin));
              // Clean up old DB entry if it exists
              try {
                await locator<ReferenceDataRepository>().deleteSetting('app_pin');
              } catch (_) {}
              if (!widget.pinEnabled) {
                await _secureStorage.write(key: 'pin_enabled', value: '1');
                try {
                  await locator<ReferenceDataRepository>().deleteSetting('pin_enabled');
                } catch (_) {}
                widget.onPinEnabledChanged(true);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حفظ رمز PIN بنجاح'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            }
          },
          isDark: widget.isDark,
        ),
        SwitchListTile(
          secondary: Icon(
            Icons.fingerprint,
            color: widget.biometricEnabled ? AppColors.primary : null,
          ),
          title: const Text('المصادقة البيومترية'),
          subtitle: Text(
            widget.isBiometricAvailable
                ? 'استخدام البصمة أو الوجه للدخول'
                : 'الجهاز لا يدعم المصادقة البيومترية',
          ),
          value: widget.biometricEnabled,
          activeColor: AppColors.primary,
          onChanged: widget.isBiometricAvailable && widget.pinEnabled
              ? (v) async {
                  if (v) {
                    // Verify biometric before enabling
                    try {
                      final localAuth = LocalAuthentication();
                      final authenticated = await localAuth.authenticate(
                        localizedReason: 'قم بالمصادقة لتفعيل الدخول بالبصمة',
                        options: AuthenticationOptions(
                          stickyAuth: true,
                          biometricOnly: true,
                        ),
                      );
                      if (authenticated) {
                        await widget.saveSetting('biometric_enabled', '1');
                        widget.onBiometricEnabledChanged(true);
                      }
                    } on PlatformException {
                      // Biometric auth failed
                    }
                  } else {
                    await widget.saveSetting('biometric_enabled', '0');
                    widget.onBiometricEnabledChanged(false);
                  }
                }
              : null,
        ),
      ],
    );
  }
}
