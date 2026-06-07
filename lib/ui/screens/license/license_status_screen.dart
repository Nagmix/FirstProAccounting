import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/license/license_constants.dart';
import '../../../core/license/license_provider.dart';
import '../../../core/license/license_models.dart';
import '../../../core/license/license_service.dart';
import '../../../core/theme/app_colors.dart';

/// Screen that displays the current license status and details.
class LicenseStatusScreen extends StatefulWidget {
  const LicenseStatusScreen({super.key});

  @override
  State<LicenseStatusScreen> createState() => _LicenseStatusScreenState();
}

class _LicenseStatusScreenState extends State<LicenseStatusScreen> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await context.read<LicenseProvider>().refresh();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _openWhatsApp() async {
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

  Color _statusColor(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.free:
        return AppColors.warning;
      case LicenseStatus.active:
        return AppColors.success;
      case LicenseStatus.expired:
        return AppColors.error;
      case LicenseStatus.revoked:
        return AppColors.accentPink;
    }
  }

  IconData _statusIcon(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.free:
        return Icons.info_outline;
      case LicenseStatus.active:
        return Icons.check_circle;
      case LicenseStatus.expired:
        return Icons.warning_amber_rounded;
      case LicenseStatus.revoked:
        return Icons.cancel;
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  String _maskKey(String? key) {
    if (key == null || key.isEmpty) return '—';
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}-****-****-${key.substring(key.length - 4)}';
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
                      AppColors.primaryDark,
                      AppColors.darkSurface,
                      AppColors.darkBackground,
                    ]
                  : [
                      AppColors.primaryDark,
                      AppColors.primary,
                      AppColors.primaryLight,
                    ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── App bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      ),
                      const Spacer(),
                      const Text(
                        'حالة الترخيص',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _isRefreshing ? null : _refresh,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, color: Colors.white),
                        tooltip: 'تحديث',
                      ),
                    ],
                  ),
                ),

                // ── Content ────────────────────────────────────────
                Expanded(
                  child: Consumer<LicenseProvider>(
                    builder: (context, provider, _) {
                      final state = provider.state;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Status badge
                            _buildStatusHeader(state),
                            const SizedBox(height: 20),

                            // Details card
                            _buildDetailsCard(state, isDark),
                            const SizedBox(height: 20),

                            // Action buttons
                            if (state.status != LicenseStatus.active) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                        context, '/license-activation');
                                  },
                                  icon: const Icon(Icons.vpn_key, size: 20),
                                  label: const Text(
                                    'تفعيل الترخيص',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            // WhatsApp support
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: _openWhatsApp,
                                icon: const Icon(Icons.chat, size: 20),
                                label: const Text(
                                  'تواصل مع الدعم عبر واتساب',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(LicenseStateModel state) {
    final color = _statusColor(state.status);
    return Container(
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
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(_statusIcon(state.status), size: 36, color: color),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              state.status.arabicLabel,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.licenseType.arabicLabel,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          // Days remaining for non-lifetime
          if (state.licenseType != LicenseType.lifetime &&
              state.status == LicenseStatus.active &&
              state.daysRemaining != null) ...[
            const SizedBox(height: 4),
            Text(
              'متبقي ${state.daysRemaining} يوم',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: (state.daysRemaining ?? 0) <= 7
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsCard(LicenseStateModel state, bool isDark) {
    final cardColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final subtitleColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final dividerColor =
        isDark ? AppColors.darkDivider : AppColors.divider;

    final remaining = LicenseService.instance.getRemainingRecords();
    final recordLabel = state.isPremium
        ? '${state.recordCount} سجل — غير محدود'
        : '${state.recordCount} / ${LicenseConstants.freeRecordLimit} سجل';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تفاصيل الترخيص',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          _detailRow(
            Icons.vpn_key_outlined,
            'مفتاح الترخيص',
            _maskKey(state.licenseKey),
            subtitleColor,
          ),
          _divider(dividerColor),
          _detailRow(
            Icons.category_outlined,
            'نوع الترخيص',
            state.licenseType.arabicLabel,
            subtitleColor,
          ),
          _divider(dividerColor),
          _detailRow(
            Icons.verified_outlined,
            'حالة الترخيص',
            state.status.arabicLabel,
            subtitleColor,
          ),
          _divider(dividerColor),
          if (state.expiresAt != null) ...[
            _detailRow(
              Icons.event_outlined,
              'تاريخ الانتهاء',
              _formatDate(state.expiresAt),
              subtitleColor,
            ),
            _divider(dividerColor),
          ] else if (state.licenseType == LicenseType.lifetime &&
              state.status == LicenseStatus.active) ...[
            _detailRow(
              Icons.all_inclusive,
              'تاريخ الانتهاء',
              'غير محدود (ترخيص دائم)',
              subtitleColor,
            ),
            _divider(dividerColor),
          ],
          _detailRow(
            Icons.storage_outlined,
            'استخدام السجلات',
            recordLabel,
            subtitleColor,
          ),
          // Progress bar for free edition
          if (!state.isPremium) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: state.recordCount / LicenseConstants.freeRecordLimit,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  remaining <= 50 ? AppColors.warning : AppColors.primary,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              remaining > 0
                  ? 'متبقي $remaining سجل'
                  : 'تم الوصول للحد الأقصى',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: remaining <= 50 ? AppColors.warning : subtitleColor,
              ),
            ),
          ],
          _divider(dividerColor),
          _detailRow(
            Icons.fingerprint,
            'بصمة الجهاز',
            state.deviceFingerprint != null &&
                    state.deviceFingerprint!.length > 16
                ? '${state.deviceFingerprint!.substring(0, 16)}...'
                : state.deviceFingerprint ?? '—',
            subtitleColor,
          ),
          _divider(dividerColor),
          _detailRow(
            Icons.install_mobile,
            'معرف التثبيت',
            state.installationId ?? '—',
            subtitleColor,
          ),
          _divider(dividerColor),
          _detailRow(
            Icons.cloud_sync_outlined,
            'آخر تحقق',
            _formatDate(state.lastValidatedAt),
            subtitleColor,
          ),
          _divider(dividerColor),
          _detailRow(
            Icons.sync,
            'آخر مزامنة',
            _formatDate(state.lastSyncAt),
            subtitleColor,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
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
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.start,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(Color color) {
    return Divider(height: 1, thickness: 0.5, color: color);
  }
}
