import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
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
  final DatabaseHelper _db = DatabaseHelper();
  final LocalAuthentication _localAuth = LocalAuthentication();

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
      // Check if PIN is enabled
      final pinEnabled = await _db.getSetting('pin_enabled');
      _isPinEnabled = pinEnabled == '1';

      if (!_isPinEnabled) {
        // No PIN set, skip lock screen
        if (mounted) _navigateToApp();
        return;
      }

      // Load stored PIN from secure storage
      _storedPin = await _getStoredPin();

      // If no PIN stored despite being enabled, force PIN creation
      if (_storedPin == null || _storedPin!.isEmpty) {
        _isCreatingPin = true;
      }

      // Check biometric availability
      try {
        _isBiometricAvailable = await _localAuth.canCheckBiometric ||
            await _localAuth.isDeviceSupported();
        if (_isBiometricAvailable) {
          final biometricEnabled = await _db.getSetting('biometric_enabled');
          _isBiometricEnabled = biometricEnabled == '1';
        }
      } on PlatformException {
        _isBiometricAvailable = false;
      }

      // Load username
      _userName = await _db.getSetting('user_name') ?? '';

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

  Future<String?> _getStoredPin() async {
    // Try flutter_secure_storage first, fall back to SharedPreferences via DB
    try {
      // Using DatabaseHelper's settings table as storage
      // In production, this should use flutter_secure_storage
      // We store in settings with a special key
      return await _db.getSetting('app_pin');
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePin(String pin) async {
    await _db.setSetting('app_pin', pin);
    await _db.setSetting('pin_enabled', '1');
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
        options: const AuthenticationOptions(
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
      // Verifying existing PIN
      if (_enteredPin == _storedPin) {
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
            AppColors.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          PhosphorIconsRegular.calculator,
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
        color: AppColors.primary.withOpacity(0.85),
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
            color: AppColors.primary.withOpacity(0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
          color: AppColors.primary.withOpacity(0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.fingerprint,
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
                        .withOpacity(0.4),
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
        PhosphorIconsRegular.backspace,
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
        PhosphorIconsRegular.fingerprint,
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
                ? AppColors.primary.withOpacity(0.08)
                : Colors.grey[100],
            border: Border.all(
              color: isEnabled
                  ? AppColors.primary.withOpacity(0.15)
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
