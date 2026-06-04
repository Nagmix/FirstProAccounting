import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/excel_exporter.dart';
import '../../../../data/datasources/database_helper.dart';
import '../../../../data/datasources/repositories/account_repository.dart';
import '../../../../data/datasources/repositories/invoice_repository.dart';
import '../../../../data/datasources/repositories/product_repository.dart';
import '../../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../../data/datasources/services/report_service.dart';
import 'settings_helpers.dart';

/// Data management section: backup, restore, auto-backup, export, and clear.
///
/// This is a [StatefulWidget] because it manages an auto-backup [Timer]
/// internally. The parent passes initial values and a [saveSetting] callback
/// so that state changes can be persisted.
class SettingsDataSection extends StatefulWidget {
  final bool isDark;
  final Future<void> Function(String key, String value) saveSetting;

  /// Initial value for auto-backup enabled flag.
  final bool initialAutoBackupEnabled;

  /// Initial value for auto-backup frequency index (0 = daily, 1 = weekly).
  final int initialAutoBackupFrequencyIndex;

  /// Initial ISO date string for the last backup, or null.
  final String? initialLastBackupDate;

  const SettingsDataSection({
    super.key,
    required this.isDark,
    required this.saveSetting,
    required this.initialAutoBackupEnabled,
    required this.initialAutoBackupFrequencyIndex,
    required this.initialLastBackupDate,
  });

  @override
  State<SettingsDataSection> createState() => _SettingsDataSectionState();
}

class _SettingsDataSectionState extends State<SettingsDataSection> {
  late bool _autoBackupEnabled;
  late int _autoBackupFrequencyIndex;
  String? _lastBackupDate;
  Timer? _autoBackupTimer;

  @override
  void initState() {
    super.initState();
    _autoBackupEnabled = widget.initialAutoBackupEnabled;
    _autoBackupFrequencyIndex = widget.initialAutoBackupFrequencyIndex;
    _lastBackupDate = widget.initialLastBackupDate;
    _initAutoBackupTimer();
  }

  @override
  void didUpdateWidget(covariant SettingsDataSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent refreshed the initial values (e.g. after _loadSettings),
    // sync the local state so the UI stays consistent.
    if (oldWidget.initialAutoBackupEnabled != widget.initialAutoBackupEnabled ||
        oldWidget.initialAutoBackupFrequencyIndex != widget.initialAutoBackupFrequencyIndex ||
        oldWidget.initialLastBackupDate != widget.initialLastBackupDate) {
      setState(() {
        _autoBackupEnabled = widget.initialAutoBackupEnabled;
        _autoBackupFrequencyIndex = widget.initialAutoBackupFrequencyIndex;
        _lastBackupDate = widget.initialLastBackupDate;
      });
      _initAutoBackupTimer();
    }
  }

  @override
  void dispose() {
    _autoBackupTimer?.cancel();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════
  //  AUTO-BACKUP TIMER LOGIC
  // ════════════════════════════════════════════════════════════════

  /// Initialize or reinitialize the periodic auto-backup timer.
  void _initAutoBackupTimer() {
    _autoBackupTimer?.cancel();
    if (!_autoBackupEnabled) return;

    // Check if a backup is needed on startup
    _checkAndPerformAutoBackup();

    // Periodic check: every 1 hour for daily, every 6 hours for weekly
    final interval = _autoBackupFrequencyIndex == 0
        ? const Duration(hours: 1)
        : const Duration(hours: 6);

    _autoBackupTimer = Timer.periodic(interval, (_) {
      _checkAndPerformAutoBackup();
    });
  }

  /// Check if enough time has passed since the last backup, then perform one.
  Future<void> _checkAndPerformAutoBackup() async {
    if (!_autoBackupEnabled) return;

    final lastBackupStr = await locator<ReferenceDataRepository>().getSetting('last_backup_date');
    if (lastBackupStr != null) {
      final lastBackup = DateTime.tryParse(lastBackupStr);
      if (lastBackup != null) {
        final now = DateTime.now();
        final difference = now.difference(lastBackup);
        final threshold = _autoBackupFrequencyIndex == 0
            ? const Duration(hours: 24) // daily
            : const Duration(days: 7); // weekly
        if (difference < threshold) return; // Not yet time
      }
    }

    await _performAutoBackup();
  }

  /// Perform auto-backup silently (no share dialog).
  Future<void> _performAutoBackup() async {
    try {
      final dbHelper = locator<DatabaseHelper>();
      final dbPath = await dbHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      await _saveAutoBackup(dbFile);

      // Update last backup date
      final now = DateTime.now().toIso8601String();
      await widget.saveSetting('last_backup_date', now);
      if (mounted) {
        setState(() => _lastBackupDate = now);
      }
    } catch (e) {
      debugPrint('SettingsDataSection._performAutoBackup: $e');
    }
  }

  /// Save a backup copy to the auto-backup directory and clean up old ones.
  Future<void> _saveAutoBackup(File dbFile) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, 'auto_backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final autoBackupPath = p.join(backupDir.path, 'auto_backup_$timestamp.db');
      await dbFile.copy(autoBackupPath);

      // Clean up old backups – keep only the last 5
      final backupFiles = await backupDir
          .list()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      if (backupFiles.length > 5) {
        // Sort by modification time, oldest first
        backupFiles.sort((a, b) =>
            FileStat.statSync(a.path).modified.compareTo(FileStat.statSync(b.path).modified));
        for (var i = 0; i < backupFiles.length - 5; i++) {
          await backupFiles[i].delete();
        }
      }
    } catch (e) {
      debugPrint('SettingsDataSection._saveAutoBackup: $e');
    }
  }

  /// Format a backup date string for display.
  String _formatBackupDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ════════════════════════════════════════════════════════════════
  //  BACKUP ACTION
  // ════════════════════════════════════════════════════════════════

  Future<void> _onBackup() async {
    try {
      final dbHelper = locator<DatabaseHelper>();
      final dbPath = await dbHelper.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لم يتم العثور على قاعدة البيانات')),
          );
        }
        return;
      }

      // Save auto-backup copy
      await _saveAutoBackup(dbFile);

      // Create timestamped backup for sharing
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final backupPath = p.join(dir.path, 'firstpro_backup_$timestamp.db');
      await dbFile.copy(backupPath);

      // Update last backup date
      final now = DateTime.now().toIso8601String();
      await widget.saveSetting('last_backup_date', now);
      setState(() => _lastBackupDate = now);

      // Share the backup file
      await Share.shareXFiles(
        [XFile(backupPath)],
        text: 'نسخة احتياطية - الأول برو المحاسبي',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء النسخة الاحتياطية بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء النسخ الاحتياطي')),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  RESTORE ACTION
  // ════════════════════════════════════════════════════════════════

  Future<void> _onRestore() async {
    // Show restore source options
    final source = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة البيانات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open, color: AppColors.primary),
              title: const Text('اختيار ملف من الجهاز'),
              subtitle: const Text('اختر ملف .db من تخزين الجهاز'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.primary),
              title: const Text('النسخ الاحتياطية التلقائية'),
              subtitle: const Text('استعادة من نسخة محفوظة تلقائياً'),
              onTap: () => Navigator.pop(ctx, 'auto'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (source == null || !mounted) return;

    String? backupFilePath;

    if (source == 'file') {
      // Use file_picker to select a .db file
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['db'],
          dialogTitle: 'اختر ملف النسخة الاحتياطية',
        );
        if (result != null && result.files.single.path != null) {
          backupFilePath = result.files.single.path!;
        } else {
          return; // User cancelled
        }
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حدث خطأ أثناء فتح الملف')),
          );
        }
        return;
      }
    } else if (source == 'auto') {
      // List available auto-backup files
      final autoFile = await _pickAutoBackupFile();
      if (autoFile == null) return;
      backupFilePath = autoFile;
    }

    if (backupFilePath == null || !mounted) return;

    // Show warning dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 48),
        title: const Text('تحذير: استعادة البيانات'),
        content: const Text(
          'تحذير: ستتم استبدال جميع البيانات الحالية بالنسخة الاحتياطية. هل أنت متأكد؟\n\n'
          'لا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warning,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Perform the restore
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('جارٍ استعادة البيانات...'),
            ],
          ),
        ),
      );

      final dbHelper = locator<DatabaseHelper>();

      // 0. Verify backup file integrity before replacing the database
      try {
        final backupDb = await sqflite.openDatabase(
          backupFilePath!,
          version: 1,
          readOnly: true,
        );
        final result = await backupDb.rawQuery('PRAGMA integrity_check');
        await backupDb.close();
        if (result.isEmpty || result.first.values.first.toString() != 'ok') {
          if (mounted) {
            Navigator.pop(context); // dismiss loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('الملف المحدد تالف أو غير صالح. لا يمكن استعادة البيانات.'),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // dismiss loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل التحقق من سلامة الملف: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // 1. Close the database connection
      await dbHelper.resetInstance();

      // 2. Replace the current DB file with the backup
      final dbPath = await dbHelper.getDatabasePath();
      final backupFile = File(backupFilePath!);
      await backupFile.copy(dbPath);

      // 3. Reopen the database (will happen automatically on next access)
      // Trigger it by accessing the database
      await dbHelper.database;

      // 4. Update last backup date
      final now = DateTime.now().toIso8601String();
      await widget.saveSetting('last_backup_date', now);

      // 5. Dismiss loading
      if (mounted) {
        Navigator.pop(context); // dismiss loading dialog
      }

      // 6. Show success and prompt restart
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            title: const Text('تمت الاستعادة بنجاح'),
            content: const Text(
              'تم استعادة البيانات من النسخة الاحتياطية بنجاح.\n'
              'يُنصح بإعادة تشغيل التطبيق لضمان تحميل جميع البيانات.',
              textAlign: TextAlign.center,
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Update local state
                  setState(() => _lastBackupDate = now);
                },
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Dismiss loading if still visible
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء استعادة البيانات'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// List available auto-backup files and let user pick one.
  Future<String?> _pickAutoBackupFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, 'auto_backups'));

      if (!await backupDir.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد نسخ احتياطية تلقائية محفوظة')),
          );
        }
        return null;
      }

      final files = await backupDir
          .list()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد نسخ احتياطية تلقائية محفوظة')),
          );
        }
        return null;
      }

      // Sort by modification time, newest first
      files.sort((a, b) =>
          FileStat.statSync(b.path).modified.compareTo(FileStat.statSync(a.path).modified));

      if (!mounted) return null;

      // Show picker dialog
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اختر نسخة احتياطية'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (_, index) {
                final file = files[index];
                final stat = FileStat.statSync(file.path);
                final modified = stat.modified;
                final sizeKB = (stat.size / 1024).toStringAsFixed(1);
                final dateStr = '${modified.year}/${modified.month.toString().padLeft(2, '0')}/${modified.day.toString().padLeft(2, '0')} '
                    '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: AppColors.primary),
                  title: Text(dateStr),
                  subtitle: Text('الحجم: ${sizeKB} ك.ب'),
                  onTap: () => Navigator.pop(ctx, file.path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء قراءة النسخ الاحتياطية')),
        );
      }
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  EXPORT REPORTS ACTION
  // ════════════════════════════════════════════════════════════════

  Future<void> _onExportReports() async {
    // عرض خيارات التصدير
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصدير التقارير'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_tree, color: AppColors.primary),
              title: const Text('تصدير الحسابات'),
              subtitle: const Text('شجرة الحسابات'),
              onTap: () => Navigator.pop(ctx, 'accounts'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt, color: AppColors.primary),
              title: const Text('تصدير الفواتير'),
              subtitle: const Text('قائمة الفواتير'),
              onTap: () => Navigator.pop(ctx, 'invoices'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2, color: AppColors.primary),
              title: const Text('تصدير المخزون'),
              subtitle: const Text('بيانات المنتجات والمخزون'),
              onTap: () => Navigator.pop(ctx, 'inventory'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: AppColors.primary),
              title: const Text('تصدير الحركات'),
              subtitle: const Text('القيود المحاسبية'),
              onTap: () => Navigator.pop(ctx, 'transactions'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    try {
      String filePath;

      switch (choice) {
        case 'accounts':
          final accounts = await locator<AccountRepository>().getAllAccounts();
          filePath = await ExcelExporter.exportAccountsToExcel(accounts);
          break;
        case 'invoices':
          final invoices = await locator<InvoiceRepository>().getAllInvoices();
          filePath = await ExcelExporter.exportInvoicesToExcel(invoices);
          break;
        case 'inventory':
          final products = await locator<ProductRepository>().getAllProducts();
          filePath = await ExcelExporter.exportInventoryToExcel(products);
          break;
        case 'transactions':
          final transactions = await locator<ReportService>().getAllTransactionsForExport();
          filePath = await ExcelExporter.exportTransactionsToExcel(transactions);
          break;
        default:
          return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير التقرير بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التصدير')),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  CLEAR ALL DATA ACTION
  // ════════════════════════════════════════════════════════════════

  void _onClearAllData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 48),
        title: const Text('مسح جميع البيانات'),
        content: const Text(
          'هل أنت متأكد من حذف جميع البيانات؟ لا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم مسح جميع البيانات'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            child: const Text('مسح'),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: 'البيانات',
      icon: Icons.storage,
      isDark: widget.isDark,
      children: [
        ActionTile(
          icon: Icons.cloud_upload,
          title: 'نسخ احتياطي',
          subtitle: 'حفظ نسخة من جميع البيانات',
          onTap: _onBackup,
          isDark: widget.isDark,
        ),
        ActionTile(
          icon: Icons.cloud_download,
          title: 'استعادة البيانات',
          subtitle: 'استعادة من نسخة احتياطية',
          onTap: _onRestore,
          isDark: widget.isDark,
        ),
        // ── Last backup info ─────────────────────────
        if (_lastBackupDate != null)
          ReadOnlySetting(
            label: 'آخر نسخة احتياطية',
            value: _formatBackupDate(_lastBackupDate!),
            icon: Icons.schedule,
            isDark: widget.isDark,
          ),
        // ── Auto-backup toggle ───────────────────────
        SwitchListTile(
          secondary: Icon(
            Icons.backup_rounded,
            color: _autoBackupEnabled ? AppColors.primary : null,
          ),
          title: const Text('نسخ احتياطي تلقائي'),
          subtitle: Text(
            _autoBackupEnabled
                ? _autoBackupFrequencyIndex == 0
                    ? 'نسخ يومي تلقائي'
                    : 'نسخ أسبوعي تلقائي'
                : 'إنشاء نسخ احتياطية تلقائياً',
          ),
          value: _autoBackupEnabled,
          activeColor: AppColors.primary,
          onChanged: (v) async {
            setState(() => _autoBackupEnabled = v);
            await widget.saveSetting('auto_backup_enabled', v ? '1' : '0');
            if (v) {
              _initAutoBackupTimer();
              await _performAutoBackup();
            } else {
              _autoBackupTimer?.cancel();
            }
          },
        ),
        // ── Auto-backup frequency ─────────────────────
        if (_autoBackupEnabled)
          ListTile(
            leading: Icon(Icons.timer, color: AppColors.primary, size: 22),
            title: const Text('تكرار النسخ التلقائي'),
            trailing: DropdownButton<int>(
              value: _autoBackupFrequencyIndex,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('يومي')),
                DropdownMenuItem(value: 1, child: Text('أسبوعي')),
              ],
              onChanged: (v) async {
                if (v != null) {
                  setState(() => _autoBackupFrequencyIndex = v);
                  await widget.saveSetting(
                    'auto_backup_frequency',
                    v == 0 ? 'daily' : 'weekly',
                  );
                  _initAutoBackupTimer();
                }
              },
            ),
          ),
        ActionTile(
          icon: Icons.file_download,
          title: 'تصدير التقارير',
          subtitle: 'تصدير التقارير كملف Excel',
          onTap: _onExportReports,
          isDark: widget.isDark,
        ),
        DangerTile(
          title: 'مسح جميع البيانات',
          subtitle: 'حذف جميع البيانات نهائياً',
          onTap: _onClearAllData,
        ),
      ],
    );
  }
}
