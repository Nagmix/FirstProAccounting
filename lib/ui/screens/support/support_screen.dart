import 'package:flutter/material.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/date_formatter.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

/// Support and complaints screen for the FirstPro accounting app.
///
/// Features a TabBar with two tabs:
/// 1. شكوى جديدة – New complaint form
/// 2. شكاوى سابقة – Previous complaints list
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── New complaint form controllers ──────────────────────────────
  final _customerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedCountry = 'اليمن';
  String _complaintType = 'فني'; // فني / مالي / خدمي

  // ── Previous complaints (loaded from DB) ────────────────────────
  final List<_Complaint> _previousComplaints = [];

  // ── Country options with flags ──────────────────────────────────
  static const List<_CountryOption> _countries = [
    _CountryOption(name: 'اليمن', flag: '🇾🇪'),
    _CountryOption(name: 'السعودية', flag: '🇸🇦'),
    _CountryOption(name: 'الإمارات', flag: '🇦🇪'),
    _CountryOption(name: 'مصر', flag: '🇪🇬'),
    _CountryOption(name: 'العراق', flag: '🇮🇶'),
    _CountryOption(name: 'الأردن', flag: '🇯🇴'),
    _CountryOption(name: 'الكويت', flag: '🇰🇼'),
    _CountryOption(name: 'البحرين', flag: '🇧🇭'),
    _CountryOption(name: 'عُمان', flag: '🇴🇲'),
    _CountryOption(name: 'قطر', flag: '🇶🇦'),
    _CountryOption(name: 'لبنان', flag: '🇱🇧'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadComplaintsFromDb();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerNameController.dispose();
    _phoneController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── Load complaints from notifications table ────────────────────
  Future<void> _loadComplaintsFromDb() async {
    try {
      final rows = await locator<ReferenceDataRepository>()
          .getNotificationsByType('complaint');
      if (!mounted) return;
      setState(() {
        _previousComplaints.clear();
        for (final row in rows) {
          _previousComplaints.add(_Complaint.fromMap(row));
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء تحميل البيانات'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('قسم الدعم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () {
              // TODO: Search complaints
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'شكوى جديدة'),
            Tab(text: 'شكاوى سابقة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewComplaintTab(theme),
          _buildPreviousComplaintsTab(theme),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 1: NEW COMPLAINT FORM
  // ════════════════════════════════════════════════════════════════
  Widget _buildNewComplaintTab(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Customer name ───────────────────────────────────
            Text(
              'اسم العميل',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _customerNameController,
              decoration: InputDecoration(
                hintText: 'أدخل اسم العميل',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Phone number ────────────────────────────────────
            Text(
              'رقم الهاتف',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '05XXXXXXXX',
                prefixIcon: const Icon(Icons.phone_android, size: 20),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Subject ─────────────────────────────────────────
            Text(
              'العنوان',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                hintText: 'عنوان الشكوى',
                prefixIcon: const Icon(Icons.title, size: 20),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Country dropdown ────────────────────────────────
            Text(
              'الدولة',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedCountry,
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _countries
                  .map((c) => DropdownMenuItem(
                        value: c.name,
                        child: Text('${c.flag}  ${c.name}'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedCountry = v);
              },
            ),
            const SizedBox(height: 16),

            // ── Description ─────────────────────────────────────
            Text(
              'وصف الشكوى',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'اكتب تفاصيل الشكوى هنا...',
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Complaint type (radio buttons) ──────────────────
            Text(
              'نوع الشكوى',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('فني'),
                    value: 'فني',
                    groupValue: _complaintType,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (v) {
                      if (v != null) setState(() => _complaintType = v);
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('مالي'),
                    value: 'مالي',
                    groupValue: _complaintType,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (v) {
                      if (v != null) setState(() => _complaintType = v);
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('خدمي'),
                    value: 'خدمي',
                    groupValue: _complaintType,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (v) {
                      if (v != null) setState(() => _complaintType = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Attach image button ─────────────────────────────
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Implement image attachment
              },
              icon: const Icon(Icons.camera_alt_outlined, size: 20),
              label: const Text('إرفاق صورة'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // ── Submit button ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitComplaint,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'إرسال الشكوى',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 2: PREVIOUS COMPLAINTS
  // ════════════════════════════════════════════════════════════════
  Widget _buildPreviousComplaintsTab(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_previousComplaints.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'لا توجد شكاوى سابقة',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadComplaintsFromDb,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _previousComplaints.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final complaint = _previousComplaints[index];
          return _ComplaintCard(complaint: complaint, isDark: isDark);
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  ACTIONS
  // ════════════════════════════════════════════════════════════════
  Future<void> _submitComplaint() async {
    if (_customerNameController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ملء جميع الحقول المطلوبة'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final customerName = _customerNameController.text.trim();
    final subject = _subjectController.text.trim().isEmpty
        ? 'شكوى جديدة'
        : _subjectController.text.trim();
    final phone = _phoneController.text.trim();
    final description = _descriptionController.text.trim();
    final now = DateTime.now();

    // Build the notification body with all complaint details
    final body = 'العميل: $customerName'
        '${phone.isNotEmpty ? ' | الهاتف: $phone' : ''}'
        ' | الدولة: $_selectedCountry'
        ' | النوع: $_complaintType'
        '\n$description';

    // Save to notifications table in the database
    await locator<ReferenceDataRepository>().insertNotification({
      'title': subject,
      'body': body,
      'type': 'complaint',
      'reference_id': 'CMP-${now.millisecondsSinceEpoch}',
      'is_read': 0,
      'created_at': now.toIso8601String(),
    });

    // Add to local list and update UI
    setState(() {
      _previousComplaints.insert(
        0,
        _Complaint(
          customerName: customerName,
          subject: subject,
          type: _complaintType,
          status: ComplaintStatus.open,
          date: now,
        ),
      );
    });

    // Clear form
    _customerNameController.clear();
    _phoneController.clear();
    _subjectController.clear();
    _descriptionController.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إرسال الشكوى بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );

    // Switch to previous complaints tab
    _tabController.animateTo(1);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  COMPLAINT MODEL
// ═══════════════════════════════════════════════════════════════════
enum ComplaintStatus { open, inProgress, closed }

class _Complaint {
  const _Complaint({
    required this.customerName,
    required this.subject,
    required this.type,
    required this.status,
    required this.date,
  });

  final String customerName;
  final String subject;
  final String type;
  final ComplaintStatus status;
  final DateTime date;

  /// Create a _Complaint from a notifications table row.
  factory _Complaint.fromMap(Map<String, dynamic> map) {
    final body = (map['body'] as String?) ?? '';
    // Parse customer name from the stored body format:
    // "العميل: أحمد | الهاتف: 05XX | الدولة: اليمن | النوع: فني\nDescription"
    String customerName = '';
    String type = 'فني';
    final bodyParts = body.split('\n');
    if (bodyParts.isNotEmpty) {
      final metaLine = bodyParts[0];
      final metaParts = metaLine.split(' | ');
      for (final part in metaParts) {
        if (part.startsWith('العميل:')) {
          customerName = part.replaceFirst('العميل:', '').trim();
        }
        if (part.startsWith('النوع:')) {
          type = part.replaceFirst('النوع:', '').trim();
        }
      }
    }

    // Determine status: newly inserted complaints are always "open"
    // (status changes would need a separate column or be managed server-side)
    ComplaintStatus status = ComplaintStatus.open;

    return _Complaint(
      customerName: customerName,
      subject: (map['title'] as String?) ?? 'شكوى جديدة',
      type: type,
      status: status,
      date: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  COMPLAINT CARD
// ═══════════════════════════════════════════════════════════════════
class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.complaint,
    required this.isDark,
  });

  final _Complaint complaint;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusInfo = _getStatusInfo(complaint.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // ── Type icon ───────────────────────────────────────
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusInfo.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getTypeIcon(complaint.type),
                color: statusInfo.color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // ── Details ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complaint.customerName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    complaint.subject,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormatter.timeAgo(complaint.date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),

            // ── Status badge ────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusInfo.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusInfo.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: statusInfo.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusInfo _getStatusInfo(ComplaintStatus status) {
    switch (status) {
      case ComplaintStatus.open:
        return _StatusInfo(label: 'مفتوحة', color: AppColors.error);
      case ComplaintStatus.inProgress:
        return _StatusInfo(label: 'قيد المتابعة', color: AppColors.warning);
      case ComplaintStatus.closed:
        return _StatusInfo(label: 'مغلقة', color: AppColors.success);
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'فني':
        return Icons.build_outlined;
      case 'مالي':
        return Icons.attach_money;
      case 'خدمي':
        return Icons.support_agent_outlined;
      default:
        return Icons.help_outline;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════
class _StatusInfo {
  const _StatusInfo({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;
}

class _CountryOption {
  const _CountryOption({
    required this.name,
    required this.flag,
  });

  final String name;
  final String flag;
}
