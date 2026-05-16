import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// Barcode scanner screen with manual entry fallback.
/// Returns the barcode string via Navigator.pop.
/// Note: Camera-based scanning is available via image_picker integration.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مسح الباركود'),
          actions: [
            TextButton.icon(
              onPressed: _submit,
              icon: const Icon(PhosphorIconsRegular.check, color: Colors.white),
              label: const Text('تأكيد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon header
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    PhosphorIconsFill.barcode,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'أدخل الباركود يدوياً',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'أدخل رقم الباركود الموجود على المنتج',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textHint,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Barcode input field
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'رقم الباركود',
                  hintText: 'أدخل الباركود هنا...',
                  prefixIcon: const Icon(PhosphorIconsRegular.barcode),
                  suffixIcon: IconButton(
                    icon: const Icon(PhosphorIconsRegular.x),
                    onPressed: () => _controller.clear(),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _controller.clear(),
                      icon: const Icon(PhosphorIconsRegular.backspace, size: 18),
                      label: const Text('مسح'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(PhosphorIconsRegular.check, size: 18),
                      label: const Text('بحث وتأكيد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال رقم الباركود'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    Navigator.of(context).pop(code);
  }
}
