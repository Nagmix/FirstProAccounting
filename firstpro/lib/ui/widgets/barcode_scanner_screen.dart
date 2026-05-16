import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';

/// Barcode scanner screen with camera-based scanning and manual entry fallback.
/// Returns the barcode string via Navigator.pop.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = TextEditingController();
  bool _isCameraActive = true;
  bool _hasScanned = false;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    _controller.dispose();
    _scannerController.dispose();
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
        body: Column(
          children: [
            // Camera scanner area
            Expanded(
              flex: 3,
              child: _isCameraActive
                  ? Stack(
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: (capture) {
                            if (_hasScanned) return;
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              if (barcode.rawValue != null) {
                                _hasScanned = true;
                                _controller.text = barcode.rawValue!;
                                // Haptic feedback
                                break;
                              }
                            }
                          },
                        ),
                        // Scanner overlay
                        Container(
                          decoration: ShapeDecoration(
                            shape: ScannerOverlayShape(),
                        ),
                        ),
                        // Toggle button
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() => _isCameraActive = false);
                                      },
                                      icon: const Icon(PhosphorIconsRegular.keyboard, color: Colors.white, size: 18),
                                      label: const Text('إدخال يدوي', style: TextStyle(color: Colors.white, fontSize: 13)),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () => _scannerController.switchCamera(),
                                      icon: const Icon(PhosphorIconsRegular.cameraRotate, color: Colors.white, size: 20),
                                      tooltip: 'تبديل الكاميرا',
                                    ),
                                    IconButton(
                                      onPressed: () => _scannerController.toggleTorch(),
                                      icon: const Icon(PhosphorIconsRegular.flashlight, color: Colors.white, size: 20),
                                      tooltip: 'الفلاش',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Scanned value display
                        if (_hasScanned)
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(PhosphorIconsFill.checkCircle, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'تم المسح: ${_controller.text}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _hasScanned = false);
                                    },
                                    child: const Text('إعادة', style: TextStyle(color: Colors.white70)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
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
                          const SizedBox(height: 16),
                          Text(
                            'أدخل الباركود يدوياً',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'أدخل رقم الباركود الموجود على المنتج',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textHint,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),

            // Manual input section
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Barcode input field
                    TextField(
                      controller: _controller,
                      autofocus: !_isCameraActive,
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
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _hasScanned = false;
                                if (!_isCameraActive) _isCameraActive = true;
                              });
                            },
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

                    // Switch mode button
                    if (!_isCameraActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isCameraActive = true;
                              _hasScanned = false;
                            });
                          },
                          icon: const Icon(PhosphorIconsRegular.camera, size: 18),
                          label: const Text('استخدام الكاميرا'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
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

/// Custom overlay shape for the scanner.
class ScannerOverlayShape extends ShapeBorder {
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path path = Path();
    final scanArea = Rect.fromCenter(
      center: rect.center,
      width: rect.width * 0.7,
      height: rect.height * 0.5,
    );
    path.addRect(rect);
    path.addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(16)));
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final scanArea = Rect.fromCenter(
      center: rect.center,
      width: rect.width * 0.7,
      height: rect.height * 0.5,
    );
    canvas.drawRect(rect, Paint()..color = Colors.black54);

    // Draw corner indicators
    final cornerPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    const cornerLength = 24.0;

    // Top-left
    canvas.drawLine(scanArea.topLeft, scanArea.topLeft.translate(cornerLength, 0), cornerPaint);
    canvas.drawLine(scanArea.topLeft, scanArea.topLeft.translate(0, cornerLength), cornerPaint);

    // Top-right
    canvas.drawLine(scanArea.topRight, scanArea.topRight.translate(-cornerLength, 0), cornerPaint);
    canvas.drawLine(scanArea.topRight, scanArea.topRight.translate(0, cornerLength), cornerPaint);

    // Bottom-left
    canvas.drawLine(scanArea.bottomLeft, scanArea.bottomLeft.translate(cornerLength, 0), cornerPaint);
    canvas.drawLine(scanArea.bottomLeft, scanArea.bottomLeft.translate(0, -cornerLength), cornerPaint);

    // Bottom-right
    canvas.drawLine(scanArea.bottomRight, scanArea.bottomRight.translate(-cornerLength, 0), cornerPaint);
    canvas.drawLine(scanArea.bottomRight, scanArea.bottomRight.translate(0, -cornerLength), cornerPaint);
  }

  @override
  ShapeBorder scale(double t) => this;
}
