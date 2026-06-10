import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Profile card displayed at the top of the Settings screen.
///
/// Shows the business logo, name, phone & email, and an "Edit Profile" button
/// that opens a dialog for editing all profile fields.
class SettingsProfileSection extends StatelessWidget {
  final ThemeData theme;
  final bool isDark;
  final TextEditingController businessNameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController addressController;
  final String? businessLogoPath;
  final Future<void> Function(String key, String value) saveSetting;
  final VoidCallback onProfileUpdated;

  const SettingsProfileSection({
    super.key,
    required this.theme,
    required this.isDark,
    required this.businessNameController,
    required this.phoneController,
    required this.emailController,
    required this.addressController,
    required this.businessLogoPath,
    required this.saveSetting,
    required this.onProfileUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // ── Logo ─────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              image: businessLogoPath != null
                  ? DecorationImage(
                      image: FileImage(File(businessLogoPath!)),
                      fit: BoxFit.cover)
                  : null,
            ),
            child: businessLogoPath == null
                ? const Icon(
                    Icons.business,
                    size: 36,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(height: 14),

          // ── Business name ────────────────────────────────────
          Text(
            businessNameController.text.isEmpty
                ? 'اسم النشاط التجاري'
                : businessNameController.text,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            phoneController.text.isEmpty && emailController.text.isEmpty
                ? 'أضف بيانات النشاط'
                : '${phoneController.text.isEmpty ? '—' : phoneController.text}  •  ${emailController.text.isEmpty ? '—' : emailController.text}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),

          // ── Edit profile button ──────────────────────────────
          OutlinedButton.icon(
            onPressed: () => _showEditProfileDialog(context),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('تعديل البيانات'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  EDIT PROFILE DIALOG
  // ════════════════════════════════════════════════════════════════
  void _showEditProfileDialog(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات النشاط'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo picker ──
              GestureDetector(
                onTap: () async {
                  final navigator = Navigator.of(ctx);
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 512,
                      maxHeight: 512);
                  if (picked != null) {
                    // Save to app documents directory
                    final dir = await getApplicationDocumentsDirectory();
                    final logoDir = p.join(
                        dir.path, 'business_logo${p.extension(picked.path)}');
                    await File(picked.path).copy(logoDir);
                    onProfileUpdated();
                    if (!ctx.mounted) return;
                    navigator.pop();
                    if (!parentContext.mounted) return;
                    _showEditProfileDialog(
                        parentContext); // Reopen to reflect new logo
                  }
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage: businessLogoPath != null
                      ? FileImage(File(businessLogoPath!))
                      : null,
                  child: businessLogoPath == null
                      ? const Icon(Icons.add_a_photo,
                          size: 32, color: AppColors.primary)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text('اضغط لتغيير الشعار',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              if (businessLogoPath != null)
                TextButton(
                  onPressed: () async {
                    final navigator = Navigator.of(ctx);
                    await saveSetting('business_logo_path', '');
                    onProfileUpdated();
                    if (!ctx.mounted) return;
                    navigator.pop();
                    if (!parentContext.mounted) return;
                    _showEditProfileDialog(parentContext);
                  },
                  child: const Text('إزالة الشعار',
                      style: TextStyle(fontSize: 11, color: AppColors.error)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: businessNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم النشاط التجاري',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await saveSetting('business_name', businessNameController.text);
              await saveSetting('business_phone', phoneController.text);
              await saveSetting('business_email', emailController.text);
              await saveSetting('business_address', addressController.text);
              if (businessLogoPath != null) {
                await saveSetting('business_logo_path', businessLogoPath!);
              }
              onProfileUpdated();
              if (parentContext.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
