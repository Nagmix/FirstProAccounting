import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/services/bluetooth_printer_service.dart';

/// Bluetooth thermal printer settings screen.
class BluetoothPrinterSettingsScreen extends StatefulWidget {
  const BluetoothPrinterSettingsScreen({super.key});

  @override
  State<BluetoothPrinterSettingsScreen> createState() =>
      _BluetoothPrinterSettingsScreenState();
}

class _BluetoothPrinterSettingsScreenState
    extends State<BluetoothPrinterSettingsScreen> {
  final _printerService = BluetoothPrinterService.instance;

  List<BluetoothPrinterDevice> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isBluetoothAvailable = false;
  String? _selectedAddress;
  String _statusMessage = '';

  // Settings state
  int _paperWidth = 80;
  bool _autoCut = true;
  int _fontSize = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBluetooth();
  }

  Future<void> _loadSettings() async {
    await _printerService.loadSettings();
    setState(() {
      _paperWidth = _printerService.paperWidth;
      _autoCut = _printerService.autoCut;
      _fontSize = _printerService.fontSize;
    });
  }

  Future<void> _checkBluetooth() async {
    final available = await _printerService.isBluetoothAvailable();
    setState(() {
      _isBluetoothAvailable = available;
      _statusMessage = available ? 'البلوتوث متاح' : 'البلوتوث غير متاح على هذا الجهاز';
    });

    if (available) {
      await _scanDevices();
    }
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'جاري البحث عن الأجهزة...';
    });

    try {
      final devices = await _printerService.getPairedDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _isScanning = false;
          _statusMessage = devices.isEmpty
              ? 'لم يتم العثور على أجهزة مقترنة'
              : 'تم العثور على ${devices.length} جهاز';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'حدث خطأ أثناء البحث';
        });
      }
    }
  }

  Future<void> _connectToDevice(String address, String name) async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'جاري الاتصال بـ $name...';
    });

    try {
      final success = await _printerService.connect(address);
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _selectedAddress = address;
          _statusMessage = success
              ? 'تم الاتصال بنجاح بـ $name'
              : 'فشل الاتصال بـ $name';
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم الاتصال بـ $name بنجاح'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } on PrinterException catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = e.message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'حدث خطأ غير متوقع';
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await _printerService.disconnect();
    setState(() {
      _selectedAddress = null;
      _statusMessage = 'تم قطع الاتصال';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم قطع الاتصال'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _testPrint() async {
    if (!_printerService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الطابعة غير متصلة. يرجى الاتصال أولاً'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      await _printerService.testPrint();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طباعة الاختبار'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('حدث خطأ غير متوقع'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات الطابعة البلوتوث'),
          actions: [
            IconButton(
              onPressed: _isScanning ? null : _scanDevices,
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'إعادة البحث',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Connection Status Card ───────────────────────────
              _buildConnectionStatusCard(theme, isDark),
              const SizedBox(height: 16),

              // ── Bluetooth Availability Warning ──────────────────
              if (!_isBluetoothAvailable)
                _buildUnavailableCard(theme, isDark),

              // ── Paired Devices ──────────────────────────────────
              _buildDevicesSection(theme, isDark),
              const SizedBox(height: 16),

              // ── Print Settings ──────────────────────────────────
              _buildPrintSettingsSection(theme, isDark),
              const SizedBox(height: 16),

              // ── Test Print Button ───────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _printerService.isConnected ? _testPrint : null,
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة اختبار'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  CONNECTION STATUS CARD
  // ══════════════════════════════════════════════════════════════════
  Widget _buildConnectionStatusCard(ThemeData theme, bool isDark) {
    final isConnected = _printerService.isConnected;
    final statusColor = isConnected ? AppColors.success : AppColors.textHint;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isConnected
            ? const LinearGradient(
                colors: [AppColors.success, Color(0xFF66BB6A)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              )
            : null,
        color: isConnected ? null : (isDark ? AppColors.darkSurface : AppColors.surface),
        borderRadius: DesignSystem.borderRadius16,
        boxShadow: DesignSystem.cardShadow(isLight: !isDark),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isConnected ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? Colors.white : statusColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected ? 'متصل' : 'غير متصل',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isConnected ? Colors.white : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected
                          ? _printerService.connectedName
                          : _statusMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isConnected
                            ? Colors.white70
                            : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnected)
                TextButton(
                  onPressed: _disconnect,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('قطع الاتصال'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  UNAVAILABLE CARD
  // ══════════════════════════════════════════════════════════════════
  Widget _buildUnavailableCard(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: DesignSystem.borderRadius16,
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.bluetooth_disabled, size: 40, color: AppColors.warning),
          const SizedBox(height: 12),
          Text(
            'البلوتوث غير متاح',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'تأكد من تفعيل البلوتوث على جهازك وأن التطبيق يمتلك صلاحية الوصول للبلوتوث',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  DEVICES SECTION
  // ══════════════════════════════════════════════════════════════════
  Widget _buildDevicesSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.devices, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'الأجهزة المقترنة',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (_isScanning)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_devices.isEmpty && !_isScanning)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surfaceVariant,
              borderRadius: DesignSystem.borderRadius12,
            ),
            child: Column(
              children: [
                Icon(Icons.bluetooth_searching, size: 36, color: AppColors.textHint),
                const SizedBox(height: 8),
                Text(
                  'لا توجد أجهزة مقترنة',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
                ),
                const SizedBox(height: 4),
                Text(
                  'تأكد من تشغيل الطابعة واقترانها مع الجهاز',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._devices.map((device) {
            final isSelected = _selectedAddress == device.address ||
                _printerService.connectedAddress == device.address;
            final isCurrentConnection = _printerService.connectedAddress == device.address;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _isConnecting
                    ? null
                    : () => _connectToDevice(device.address, device.name),
                borderRadius: DesignSystem.borderRadius12,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.08)
                        : (isDark ? AppColors.darkSurface : AppColors.surface),
                    borderRadius: DesignSystem.borderRadius12,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.3)
                          : (isDark ? AppColors.darkBorder : AppColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.1)
                              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isCurrentConnection
                              ? Icons.bluetooth_connected
                              : Icons.print,
                          color: isSelected ? AppColors.primary : AppColors.textHint,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              device.address,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCurrentConnection)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'متصل',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (_isConnecting && _selectedAddress == device.address)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      else
                        Icon(
                          Icons.arrow_back_ios,
                          size: 16,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  PRINT SETTINGS SECTION
  // ══════════════════════════════════════════════════════════════════
  Widget _buildPrintSettingsSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.settings, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'إعدادات الطباعة',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: DesignSystem.borderRadius12,
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              // Paper width selector
              Row(
                children: [
                  const Icon(Icons.straighten, size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('عرض الورقة', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 80, label: Text('80مم', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 58, label: Text('58مم', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_paperWidth},
                    onSelectionChanged: (v) {
                      setState(() => _paperWidth = v.first);
                      _printerService.setPaperWidth(v.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Font size selector
              Row(
                children: [
                  const Icon(Icons.text_fields, size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('حجم الخط', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('عادي', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 1, label: Text('كبير', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_fontSize},
                    onSelectionChanged: (v) {
                      setState(() => _fontSize = v.first);
                      _printerService.setFontSize(v.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Auto-cut toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('قطع تلقائي'),
                subtitle: const Text('قطع الورقة تلقائياً بعد الطباعة'),
                value: _autoCut,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setState(() => _autoCut = v);
                  _printerService.setAutoCut(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
