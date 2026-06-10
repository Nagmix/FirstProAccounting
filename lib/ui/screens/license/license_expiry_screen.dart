import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:firstpro/core/license/license_constants.dart';
import 'package:firstpro/core/license/license_provider.dart';
import 'package:firstpro/core/theme/app_colors.dart';

/// Screen shown when the license has expired.
/// Uses a warning/red gradient design to convey urgency.
class LicenseExpiryScreen extends StatelessWidget {
  const LicenseExpiryScreen({super.key});

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  String _maskKey(String? key) {
    if (key == null || key.isEmpty) return '—';
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}-****-****-${key.substring(key.length - 4)}';
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final provider = context.read<LicenseProvider>();
    final fingerprint = provider.deviceFingerprint;
    final shortFingerprint =
        fingerprint.length > 16 ? fingerprint.substring(0, 16) : fingerprint;
    final message =
        '${LicenseConstants.supportWhatsAppMessage}$shortFingerprint...';
    final url =
        'https://wa.me/${LicenseConstants.supportWhatsApp}?text=${Uri.encodeComponent(message)}';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      const Color(0xFF4A1010),
                      AppColors.darkSurface,
                      AppColors.darkBackground,
                    ]
                  : [
                      const Color(0xFFB71C1C),
                      const Color(0xFFD32F2F),
                      const Color(0xFFEF5350),
                    ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Consumer<LicenseProvider>(
                  builder: (context, provider, _) {
                    final state = provider.state;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Warning icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            size: 44,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        const Text(
                          'انتهت صلاحية الترخيص',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ترخيصك لم يعد صالحاً. قم بتجديده للاستمرار في استخدام جميع الميزات.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),

                        // Details card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                Icons.event_busy,
                                'تاريخ الانتهاء',
                                _formatDate(state.expiresAt),
                              ),
                              const SizedBox(height: 12),
                              _infoRow(
                                Icons.vpn_key_outlined,
                                'مفتاح الترخيص',
                                _maskKey(state.licenseKey),
                              ),
                              const SizedBox(height: 12),
                              _infoRow(
                                Icons.category_outlined,
                                'نوع الترخيص',
                                state.licenseType.arabicLabel,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Renew license button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(
                                  context, '/license-activation');
                            },
                            icon: const Icon(Icons.autorenew, size: 20),
                            label: const Text(
                              'تجديد الترخيص',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.error,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Continue with free edition
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pushReplacementNamed('/');
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'المتابعة بالنسخة المجانية',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // WhatsApp support
                        TextButton.icon(
                          onPressed: () => _openWhatsApp(context),
                          icon: const Icon(Icons.chat, color: Colors.white70),
                          label: const Text(
                            'تواصل مع الدعم عبر واتساب',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.start,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
