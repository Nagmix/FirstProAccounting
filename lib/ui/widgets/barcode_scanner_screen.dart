import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';

/// Barcode scanner screen using device camera with manual entry fallback.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final _manualController = TextEditingController();
  bool _hasScanned = false;
  bool _showManualEntry = false;
  bool _cameraError = false;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode != null && barcode.rawValue != null) {
      _hasScanned = true;
      Navigator.of(context).pop(barcode.rawValue);
    }
  }

  void _submitManual() {
    final text = _manualController.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مسح الباركود'),
          actions: [
            TextButton.icon(
              onPressed: () => setState(() => _showManualEntry = !_showManualEntry),
              icon: Icon(_showManualEntry ? Icons.camera_alt : Icons.keyboard, size: 20),
              label: Text(_showManualEntry ? 'الكاميرا' : 'إدخال يدوي'),
            ),
          ],
        ),
        body: _showManualEntry ? _buildManualEntry(theme) : _buildScanner(theme),
      ),
    );
  }

  Widget _buildManualEntry(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.qr_code, size: 64, color: AppColors.primary.withOpacity(0.3)),
          const SizedBox(height: 20),
          TextField(
            controller: _manualController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitManual(),
            decoration: InputDecoration(
              labelText: 'أدخل الباركود يدوياً',
              prefixIcon: const Icon(Icons.qr_code),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                onPressed: _submitManual,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitManual,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('تأكيد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner(ThemeData theme) {
    if (_cameraError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 64, color: AppColors.warning),
            const SizedBox(height: 16),
            Text('لا يمكن الوصول إلى الكاميرا', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _showManualEntry = true),
              icon: Icon(Icons.keyboard, size: 20),
              label: const Text('إدخال يدوي'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) {
            // Camera error - show fallback
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_cameraError) {
                setState(() => _cameraError = true);
              }
            });
            return const Center(child: CircularProgressIndicator());
          },
        ),
        // Scanning overlay
        Container(
          decoration: ShapeDecoration(
            shape: ScannerOverlayShape(),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: Colors.black54,
            child: Column(
              children: [
                const Text(
                  'وجّه الكاميرا نحو الباركود',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _showManualEntry = true),
                  icon: const Icon(Icons.keyboard, color: Colors.white70, size: 18),
                  label: const Text('إدخال يدوي', style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom scanner overlay with a cutout rectangle
class ScannerOverlayShape extends ShapeBorder {
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final cutoutWidth = rect.width * 0.7;
    final cutoutHeight = rect.height * 0.25;
    final cutoutLeft = (rect.width - cutoutWidth) / 2;
    final cutoutTop = (rect.height - cutoutHeight) / 2;

    return Path()
      ..addRect(rect)
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(cutoutLeft, cutoutTop, cutoutWidth, cutoutHeight),
        const Radius.circular(16),
      ))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawPath(getOuterPath(rect), paint);

    // Draw corner brackets
    final cutoutWidth = rect.width * 0.7;
    final cutoutHeight = rect.height * 0.25;
    final cutoutLeft = (rect.width - cutoutWidth) / 2;
    final cutoutTop = (rect.height - cutoutHeight) / 2;
    final bracketLen = 24.0;
    final bracketWidth = 3.0;
    final bracketColor = AppColors.primary;

    final bracketPaint = Paint()
      ..color = bracketColor
      ..strokeWidth = bracketWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(cutoutLeft, cutoutTop + bracketLen), Offset(cutoutLeft, cutoutTop), bracketPaint);
    canvas.drawLine(Offset(cutoutLeft, cutoutTop), Offset(cutoutLeft + bracketLen, cutoutTop), bracketPaint);
    // Top-right
    canvas.drawLine(Offset(cutoutLeft + cutoutWidth - bracketLen, cutoutTop), Offset(cutoutLeft + cutoutWidth, cutoutTop), bracketPaint);
    canvas.drawLine(Offset(cutoutLeft + cutoutWidth, cutoutTop), Offset(cutoutLeft + cutoutWidth, cutoutTop + bracketLen), bracketPaint);
    // Bottom-left
    canvas.drawLine(Offset(cutoutLeft, cutoutTop + cutoutHeight - bracketLen), Offset(cutoutLeft, cutoutTop + cutoutHeight), bracketPaint);
    canvas.drawLine(Offset(cutoutLeft, cutoutTop + cutoutHeight), Offset(cutoutLeft + bracketLen, cutoutTop + cutoutHeight), bracketPaint);
    // Bottom-right
    canvas.drawLine(Offset(cutoutLeft + cutoutWidth - bracketLen, cutoutTop + cutoutHeight), Offset(cutoutLeft + cutoutWidth, cutoutTop + cutoutHeight), bracketPaint);
    canvas.drawLine(Offset(cutoutLeft + cutoutWidth, cutoutTop + cutoutHeight - bracketLen), Offset(cutoutLeft + cutoutWidth, cutoutTop + cutoutHeight), bracketPaint);
  }

  @override
  ShapeBorder scale(double t) => this;
}
