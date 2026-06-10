import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../navigation/main_scaffold.dart';

/// A lock screen that appears before any other app content.
/// Supports PIN code (4-digit) and biometric authentication.
/// All text is in Arabic with RTL layout.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with TickerProviderStateMixin {
  // ── Services ────────────────────────────────────────────────
  final LocalAuthentication _localAuth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ── State ───────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isPinEnabled = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  String _userName = '';

  // PIN entry state
  String _enteredPin = '';
  String? _storedPin;
  bool _isCreatingPin = false;
  bool _isConfirmingPin = false;
  String _firstPinEntry = '';
  String? _errorMessage;

  // Animation controllers
  late AnimationController _shakeController;
  late AnimationController _successController;
  late AnimationController _dotScaleController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _successAnimation;

  // Wrong attempt tracking
  int _wrongAttempts = 0;
  bool _isLockedOut = false;
  Timer? _lockoutTimer;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initializeScreen();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _successController.dispose();
    _dotScaleController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  // ── Initialization ──────────────────────────────────────────

  void _initAnimations() {
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _dotScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _successAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _successController, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _initializeScreen() async {
    try {
      // Load or generate per-installation salt (C-04 / H-01)
      _pinSalt = await _getOrCreatePinSalt();

      // Check if PIN is enabled (secure storage with DB fallback for migration)
      final pinEnabled = await _readSecureWithMigration('pin_enabled');
      _isPinEnabled = pinEnabled == '1';

      if (!_isPinEnabled) {
        // No PIN set, skip lock screen
        if (mounted) _navigateToApp();
        return;
      }

      // Load stored PIN from secure storage (with DB fallback for migration)
      _storedPin = await _getStoredPin();

      // If no PIN stored despite being enabled, force PIN creation
      if (_storedPin == null || _storedPin!.isEmpty) {
        _isCreatingPin = true;
      }

      // Check biometric availability
      try {
        _isBiometricAvailable = await _localAuth.isDeviceSupported();
        if (_isBiometricAvailable) {
          final biometricEnabled = await locator<ReferenceDataRepository>().getSetting('biometric_enabled');
          _isBiometricEnabled = biometricEnabled == '1';
        }
      } on PlatformException {
        _isBiometricAvailable = false;
      }

      // Load username
      _userName = await locator<ReferenceDataRepository>().getSetting('user_name') ?? '';

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Auto-trigger biometric if available and enabled
        if (_isBiometricAvailable && _isBiometricEnabled && !_isCreatingPin) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _authenticateWithBiometric();
          });
        }
      }
    } catch (e) {
      // On error, skip lock screen to avoid locking user out
      if (mounted) _navigateToApp();
    }
  }

  /// Secure SHA-256 based PIN hashing with per-installation salt (C-04).
  /// New format uses 'h3$' prefix; previous formats used 'h2$' and 'h$'.
  /// Must match the hash function used in settings_screen.dart.
  String _hashPin(String pin) {
    // Use per-installation salt if available, otherwise use a default
    // The salt is generated on first use and stored in FlutterSecureStorage
    final salt = _pinSalt;
    final key = utf8.encode('$salt$pin$salt');
    final bytes = sha256.convert(key).bytes;
    // Multiple rounds for key stretching
    var currentBytes = bytes;
    for (var round = 0; round < 1000; round++) {
      final roundKey = utf8.encode('$salt${base64Encode(currentBytes)}$pin$round');
      currentBytes = sha256.convert(roundKey).bytes;
    }
    return 'h3\$${base64Encode(currentBytes)}';
  }

  /// Per-installation salt for PIN hashing (C-04 / H-01)
  /// Generated once and stored in FlutterSecureStorage
  String? _pinSalt;

  /// Get or generate the per-installation salt
  Future<String> _getOrCreatePinSalt() async {
    try {
      var salt = await _secureStorage.read(key: 'pin_salt');
      if (salt == null || salt.isEmpty) {
        // Generate a random salt using timestamp + random values
        final random = DateTime.now().microsecondsSinceEpoch.toString() +
            DateTime.now().millisecond.toString() +
            Random().nextInt(999999).toString();
        final saltBytes = sha256.convert(utf8.encode(random)).bytes;
        salt = base64Encode(saltBytes);
        await _secureStorage.write(key: 'pin_salt', value: salt);
      }
      return salt;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLockScreen._getOrCreatePinSalt: WARNING $e');
      }
      return 'F1r5tPr0_Fallback_2024_Salt';
    }
  }

  /// Old hash function (h2 format) for backward-compatible PIN verification.
  /// Used to verify PINs stored with the 'h2$' prefix.
  String _hashPinH2(String pin) {
    const salt = 'F1r5tPr0_4cc0unt1ng_2024!@#';
    var hash = 0;
    final salted = salt + pin + salt;
    var input = salted;
    for (var round = 0; round < 100; round++) {
      hash = 0;
      for (var i = 0; i < input.length; i++) {
        hash = ((hash << 5) - hash) + input.codeUnitAt(i);
        hash = hash & 0x7fffffff;
      }
      input = '$hash$salt$pin';
    }
    return 'h2\$$hash';
  }

  /// Oldest hash function for backward-compatible PIN verification.
  /// Used to verify PINs that were stored with the old 'h$' prefix.
  String _hashPinOld(String pin) {
    int hash = 0;
    for (int i = 0; i < pin.length; i++) {
      hash = ((hash << 5) - hash) + pin.codeUnitAt(i);
      hash = hash & 0x7fffffff;
    }
    return 'h\$$hash';
  }

  /// Verify a PIN against a stored hash, supporting all formats (h3$, h2$, h$).
  bool _verifyPin(String enteredPin, String storedHash) {
    if (storedHash.startsWith('h3\$')) {
      return _hashPin(enteredPin) == storedHash;
    } else if (storedHash.startsWith('h2\$')) {
      // Old h2 format — verify using old algorithm, then re-hash with new format
      final matches = _hashPinH2(enteredPin) == storedHash;
      if (matches) {
        _upgradePinHash(enteredPin);
      }
      return matches;
    } else if (storedHash.startsWith('h\$')) {
      // Oldest format — verify using old algorithm, then re-hash with new format
      final matches = _hashPinOld(enteredPin) == storedHash;
      if (matches) {
        _upgradePinHash(enteredPin);
      }
      return matches;
    }
    return false;
  }

  /// Upgrade a PIN hash from old format to new format in secure storage.
  Future<void> _upgradePinHash(String pin) async {
    try {
      await _secureStorage.write(key: 'app_pin', value: _hashPin(pin));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLockScreen._upgradePinHash: WARNING $e');
      }
    }
  }

  Future<String?> _getStoredPin() async {
    // The stored value is a hash (prefixed with 'h' or 'h2'), not the plain PIN.
    try {
      return await _readSecureWithMigration('app_pin');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLockScreen._getStoredPin: WARNING $e');
      }
      return null;
    }
  }

  /// Read a value from FlutterSecureStorage with fallback to DB for migration.
  /// If found in DB but not in secure storage, migrates the value and removes it from DB.
  Future<String?> _readSecureWithMigration(String key) async {
    try {
      final secureValue = await _secureStorage.read(key: key);
      if (secureValue != null) return secureValue;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLockScreen._readSecureWithMigration (secureStorage): WARNING $e');
      }
    }

    // Fallback to DB for users upgrading from older versions
    try {
      final dbValue = await locator<ReferenceDataRepository>().getSetting(key);
      if (dbValue != null && dbValue.isNotEmpty) {
        // Migrate to secure storage
        await _secureStorage.write(key: key, value: dbValue);
        // Remove from DB after successful migration
        await locator<ReferenceDataRepository>().deleteSetting(key);
        return dbValue;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLockScreen._readSecureWithMigration (dbFallback): WARNING $e');
      }
    }
    return null;
  }

  Future<void> _savePin(String pin) async {
    await _secureStorage.write(key: 'app_pin', value: _hashPin(pin));
    await _secureStorage.write(key: 'pin_enabled', value: '1');
    // Clean up old DB entries if they exist
    try {
      await locator<ReferenceDataRepository>().deleteSetting('app_pin');
      await locator<ReferenceDataRepository>().deleteSetting('pin_enabled');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLockScreen._savePin: WARNING $e');
      }
    }
  }

  // ── Navigation ──────────────────────────────────────────────

  void _navigateToApp() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainScaffold(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  // ── Biometric Authentication ────────────────────────────────

  Future<void> _authenticateWithBiometric() async {
    if (!_isBiometricAvailable || _isLockedOut) return;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'قم بالمصادقة للدخول إلى التطبيق',
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        _onAuthSuccess();
      }
    } on PlatformException {
      // Biometric auth failed or was cancelled — user can still use PIN
    }
  }

  // ── PIN Entry Logic ─────────────────────────────────────────

  void _onDigitPressed(String digit) {
    if (_isLockedOut || _enteredPin.length >= 4) return;

    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    // Animate the dot fill
    _dotScaleController.forward(from: 0);

    // When 4 digits entered
    if (_enteredPin.length == 4) {
      _processPinEntry();
    }
  }

  void _onBackspacePressed() {
    if (_isLockedOut || _enteredPin.isEmpty) return;

    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _processPinEntry() async {
    if (_isCreatingPin) {
      if (!_isConfirmingPin) {
        // First entry of new PIN
        setState(() {
          _firstPinEntry = _enteredPin;
          _enteredPin = '';
          _isConfirmingPin = true;
        });
      } else {
        // Confirming new PIN
        if (_enteredPin == _firstPinEntry) {
          await _savePin(_enteredPin);
          _onAuthSuccess();
        } else {
          // PINs don't match
          _onWrongPin();
          setState(() {
            _errorMessage = 'رمز PIN غير متطابق، حاول مرة أخرى';
            _isConfirmingPin = false;
            _firstPinEntry = '';
          });
        }
      }
    } else {
      // Verifying existing PIN — compare hash of entered PIN with stored hash
      // Supports both old (h$) and new (h2$) hash formats
      if (_storedPin != null && _verifyPin(_enteredPin, _storedPin!)) {
        _onAuthSuccess();
      } else {
        _onWrongPin();
      }
    }
  }

  void _onAuthSuccess() {
    _successController.forward().then((_) {
      if (mounted) {
        _navigateToApp();
      }
    });
  }

  void _onWrongPin() {
    _wrongAttempts++;
    _shakeController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _enteredPin = '';
          if (!_isCreatingPin) {
            _errorMessage = 'رمز PIN غير صحيح';
          }
        });
      }
    });

    // Lock out after 5 wrong attempts
    if (_wrongAttempts >= 5) {
      _startLockout();
    }
  }

  void _startLockout() {
    setState(() {
      _isLockedOut = true;
      _lockoutSeconds = 30;
      _errorMessage = 'تم تجاوز عدد المحاولات، حاول بعد 30 ثانية';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _lockoutSeconds--;
        _errorMessage = 'تم تجاوز عدد المحاولات، حاول بعد $_lockoutSeconds ثانية';
      });

      if (_lockoutSeconds <= 0) {
        timer.cancel();
        setState(() {
          _isLockedOut = false;
          _wrongAttempts = 0;
          _errorMessage = null;
        });
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_isLoading) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _successAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: 1.0 - _successAnimation.value,
              child: Transform.scale(
                scale: 1.0 - (_successAnimation.value * 0.05),
                child: child,
              ),
            );
          },
          child: _buildLockContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAppLogo(size: 80),
            const SizedBox(height: 24),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockContent() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _buildHeaderSection(),
        ),
        Expanded(
          flex: 2,
          child: _buildPinDots(),
        ),
        Expanded(
          flex: 5,
          child: _buildNumericKeypad(),
        ),
      ],
    );
  }

  // ── Header Section ──────────────────────────────────────────

  Widget _buildHeaderSection() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAppLogo(),
            const SizedBox(height: 16),
            _buildAppName(),
            const SizedBox(height: 12),
            _buildGreeting(),
            const SizedBox(height: 8),
            _buildSubtext(),
            if (_isBiometricAvailable && _isBiometricEnabled && !_isCreatingPin)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildBiometricButton(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppLogo({double size = 64}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.calculate,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }

  Widget _buildAppName() {
    return Text(
      'الأول برو المحاسبي',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 0.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildGreeting() {
    if (_userName.isEmpty) return const SizedBox.shrink();

    return Text(
      'مرحباً، $_userName',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.primary.withValues(alpha: 0.85),
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtext() {
    final String text;
    if (_isCreatingPin && !_isConfirmingPin) {
      text = 'أدخل رمز PIN الجديد';
    } else if (_isCreatingPin && _isConfirmingPin) {
      text = 'أعد إدخال رمز PIN للتأكيد';
    } else {
      text = 'أدخل رمز PIN للدخول';
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        color: Colors.grey[600],
      ),
      textAlign: TextAlign.center,
    );
  }

  // ── Biometric Button ────────────────────────────────────────

  Widget _buildBiometricButton() {
    return InkWell(
      onTap: _isLockedOut ? null : _authenticateWithBiometric,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
          color: AppColors.primary.withValues(alpha: 0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fingerprint,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              'استخدام البصمة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PIN Dots ────────────────────────────────────────────────

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final shakeOffset = _shakeAnimation.value *
            10 *
            (_shakeAnimation.value < 0.5 ? 1 : -1) *
            (1 - _shakeAnimation.value);
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return _buildPinDot(index);
            }),
          ),
          const SizedBox(height: 16),
          _buildErrorMessage(),
        ],
      ),
    );
  }

  Widget _buildPinDot(int index) {
    final bool isFilled = index < _enteredPin.length;
    final bool isError = _errorMessage != null;

    return AnimatedBuilder(
      animation: _dotScaleController,
      builder: (context, child) {
        double scale = 1.0;
        // Scale up the most recently filled dot
        if (isFilled && index == _enteredPin.length - 1) {
          scale = 1.0 + (_dotScaleController.value * 0.2) * (1 - _dotScaleController.value);
        }
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isError
              ? AppColors.error
              : isFilled
                  ? AppColors.primary
                  : Colors.transparent,
          border: Border.all(
            color: isError
                ? AppColors.error
                : isFilled
                    ? AppColors.primary
                    : Colors.grey[400]!,
            width: 2,
          ),
          boxShadow: isFilled
              ? [
                  BoxShadow(
                    color: (isError ? AppColors.error : AppColors.primary)
                        .withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    if (_errorMessage == null) return const SizedBox(height: 20);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        _errorMessage!,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.error,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Numeric Keypad ──────────────────────────────────────────

  Widget _buildNumericKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildKeypadRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _buildKeypadRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _buildKeypadRow(['7', '8', '9']),
          const SizedBox(height: 16),
          _buildKeypadRow(['biometric', '0', 'backspace']),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key == 'biometric') {
          return _buildBiometricKeyButton();
        } else if (key == 'backspace') {
          return _buildBackspaceButton();
        } else {
          return _buildDigitButton(key);
        }
      }).toList(),
    );
  }

  Widget _buildDigitButton(String digit) {
    return _KeypadButton(
      onPressed: () => _onDigitPressed(digit),
      child: Text(
        digit,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return _KeypadButton(
      onPressed: _onBackspacePressed,
      child: Icon(
        Icons.backspace,
        color: Colors.grey[500],
        size: 24,
      ),
    );
  }

  Widget _buildBiometricKeyButton() {
    if (!_isBiometricAvailable || !_isBiometricEnabled || _isCreatingPin) {
      // Empty placeholder to keep layout aligned
      return const SizedBox(width: 72, height: 72);
    }

    return _KeypadButton(
      onPressed: _isLockedOut ? null : _authenticateWithBiometric,
      child: Icon(
        Icons.fingerprint,
        color: AppColors.primary,
        size: 28,
      ),
    );
  }
}

// ── Custom Keypad Button Widget ────────────────────────────────

class _KeypadButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const _KeypadButton({
    required this.onPressed,
    required this.child,
  });

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _pressController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _pressController.reverse();
  }

  void _onTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: isEnabled ? _onTapDown : null,
        onTapUp: isEnabled ? _onTapUp : null,
        onTapCancel: isEnabled ? _onTapCancel : null,
        onTap: isEnabled ? widget.onPressed : null,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isEnabled
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.grey[100],
            border: Border.all(
              color: isEnabled
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.grey[200]!,
              width: 1.5,
            ),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}
