import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/money_helper.dart';
import '../../../data/datasources/repositories/employee_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/account_repository.dart';
import '../../../ui/widgets/empty_state.dart';
import 'employee_detail_screen.dart';

/// Professional employees management screen for the FirstPro accounting app.
///
/// Follows the same design pattern as [CustomersScreen]:
/// - Search bar for filtering by name or phone.
/// - Tab bar: الكل / نشط / غير نشط.
/// - Employee list with avatar, name, job title, phone, and balance.
/// - FAB for adding a new employee via [AddEmployeeSheet].
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _searchQuery = _searchController.text.trim());
      });
    });
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    try {
      final employees =
          await locator<ReferenceDataRepository>().getAllEmployees();
      if (mounted) {
        setState(() {
          _employees = employees;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Filter logic ──────────────────────────────────────────────
  List<Map<String, dynamic>> _filterEmployees(int tabIndex) {
    var filtered = _employees;

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        final phone = (e['phone'] as String? ?? '').toLowerCase();
        final jobTitle = (e['job_title'] as String? ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q) || jobTitle.contains(q);
      }).toList();
    }

    // Apply tab filter
    switch (tabIndex) {
      case 1: // نشط
        filtered = filtered
            .where((e) => (e['is_active'] as int?) == 1)
            .toList();
        break;
      case 2: // غير نشط
        filtered = filtered
            .where((e) => (e['is_active'] as int?) != 1)
            .toList();
        break;
      // case 0: الكل – no additional filter
    }

    return filtered;
  }

  // ── Open add-employee bottom sheet ────────────────────────────
  Future<void> _showAddEmployeeSheet({Map<String, dynamic>? employee}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddEmployeeSheet(employee: employee),
    );
    _loadEmployees();
  }

  // ── Delete employee ───────────────────────────────────────────
  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final name = employee['name'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف الموظف'),
        content: Text('هل أنت متأكد من حذف الموظف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await locator<ReferenceDataRepository>()
          .deleteEmployee(employee['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف الموظف "$name"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadEmployees();
    }
  }

  // ── Avatar color based on name ────────────────────────────────
  static const List<Color> _avatarColors = [
    Color(0xFF1A237E),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFF006064),
    Color(0xFF1B5E20),
    Color(0xFF33691E),
  ];

  Color _avatarColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (prev, e) => prev + e);
    return _avatarColors[hash % _avatarColors.length];
  }

  String _currencySymbol(String? code) {
    switch (code) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () {
              FocusScope.of(context).unfocus();
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'تصفية',
            onPressed: () {
              // TODO: Implement advanced filter dialog
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'إضافة موظف',
            onPressed: () => _showAddEmployeeSheet(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'نشط'),
            Tab(text: 'غير نشط'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث عن موظف...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Employee list ──────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterEmployees(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.people
                              : tabIndex == 1
                                  ? Icons.check_circle
                                  : Icons.block,
                          title: tabIndex == 0
                              ? 'لا يوجد موظفين'
                              : tabIndex == 1
                                  ? 'لا يوجد موظفين نشطين'
                                  : 'لا يوجد موظفين غير نشطين',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة موظفين جدد لبدء إدارة رواتبهم'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel: tabIndex == 0 ? 'إضافة موظف' : null,
                          onAction:
                              tabIndex == 0 ? () => _showAddEmployeeSheet() : null,
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final employee = filtered[index];
                          return _EmployeeCard(
                            employee: employee,
                            avatarColor: _avatarColor(
                                employee['name'] as String? ?? ''),
                            currencySymbol: _currencySymbol(
                                employee['currency'] as String?),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EmployeeDetailScreen(employee: employee),
                                ),
                              ).then((_) => _loadEmployees());
                            },
                            onDelete: () => _deleteEmployee(employee),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmployeeSheet(),
        tooltip: 'إضافة موظف',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  EMPLOYEE CARD – matches _CustomerCard pattern
// ═══════════════════════════════════════════════════════════════════
class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.avatarColor,
    required this.currencySymbol,
    this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> employee;
  final Color avatarColor;
  final String currencySymbol;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final name = employee['name'] as String? ?? '';
    final phone = employee['phone'] as String? ?? '';
    final jobTitle = employee['job_title'] as String? ?? '';
    final balance = MoneyHelper.readMoney(employee['balance']);
    final balanceType = employee['balance_type'] as String? ?? 'credit';
    final isActive = (employee['is_active'] as int?) == 1;
    final isDebit = balanceType == 'debit' && balance > 0;
    final isCredit = balanceType == 'credit' && balance > 0;

    final balanceColor = isDebit
        ? AppColors.error
        : isCredit
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: avatarColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Name, job title, phone ───────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'غير نشط',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.error,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (jobTitle.isNotEmpty) ...[
                          Icon(
                            Icons.work,
                            size: 14,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            jobTitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLight
                                  ? AppColors.textSecondary
                                  : AppColors.darkTextSecondary,
                            ),
                          ),
                          if (phone.isNotEmpty)
                            const SizedBox(width: 8),
                        ],
                        if (phone.isNotEmpty) ...[
                          Icon(
                            Icons.phone,
                            size: 14,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLight
                                  ? AppColors.textSecondary
                                  : AppColors.darkTextSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Balance ──────────────────────────────────────
              if (balance > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${balance.abs().toStringAsFixed(2)} $currencySymbol',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: balanceColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDebit ? 'عليه' : isCredit ? 'له' : 'متساوي',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: balanceColor,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '0.00 $currencySymbol',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isLight
                            ? AppColors.textSecondary
                            : AppColors.darkTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'متساوي',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isLight
                            ? AppColors.textHint
                            : AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 4),

              // ── Arrow icon ───────────────────────────────────
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD EMPLOYEE SHEET – matches AddCustomerSheet pattern
// ═══════════════════════════════════════════════════════════════════
class AddEmployeeSheet extends StatefulWidget {
  final Map<String, dynamic>? employee;

  const AddEmployeeSheet({super.key, this.employee});

  @override
  State<AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<AddEmployeeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _balanceController = TextEditingController();
  final _notesController = TextEditingController();

  String _balanceType = 'credit'; // 'credit' (له) or 'debit' (عليه)
  String _currency = 'YER';
  bool _isSaving = false;

  static const _currencyInfo = {
    'YER': {'symbol': 'ر.ي', 'label': 'ريال يمني'},
    'SAR': {'symbol': 'ر.س', 'label': 'ريال سعودي'},
    'USD': {'symbol': '\$', 'label': 'دولار أمريكي'},
  };

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      final e = widget.employee!;
      _nameController.text = e['name'] as String? ?? '';
      _phoneController.text = e['phone'] as String? ?? '';
      _jobTitleController.text = e['job_title'] as String? ?? '';
      _balanceController.text =
          MoneyHelper.readMoney(e['balance']).toStringAsFixed(2);
      _balanceType = e['balance_type'] as String? ?? 'credit';
      _currency = e['currency'] as String? ?? 'YER';
      _notesController.text = e['notes'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _jobTitleController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now().toIso8601String();
      final balance = double.tryParse(_balanceController.text) ?? 0.0;

      // Get the employee account for this currency
      int? accountId;
      final accounts =
          await locator<AccountRepository>().getAccountsByCurrency(_currency);
      int accountCodeSuffix =
          _currency == 'YER' ? 5100 : (_currency == 'SAR' ? 5101 : 5102);
      final empAccount = accounts
          .where((a) => a['account_code'] == accountCodeSuffix.toString())
          .firstOrNull;
      if (empAccount != null) {
        accountId = empAccount['id'] as int;
      }

      final data = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'job_title': _jobTitleController.text.trim().isEmpty
            ? null
            : _jobTitleController.text.trim(),
        'balance': balance,
        'balance_type': _balanceType,
        'currency': _currency,
        'account_id': accountId,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'is_active': 1,
        'updated_at': now,
      };

      final isEditing = widget.employee != null;
      if (isEditing) {
        await locator<ReferenceDataRepository>()
            .updateEmployee(widget.employee!['id'] as int, data);
      } else {
        data['created_at'] = now;
        await locator<ReferenceDataRepository>().insertEmployee(data);

        // If opening balance > 0, post journal entry
        if (balance > 0 && accountId != null) {
          int cashCodeSuffix =
              _currency == 'YER' ? 1100 : (_currency == 'SAR' ? 1101 : 1102);
          final cashAccount = accounts
              .where((a) => a['account_code'] == cashCodeSuffix.toString())
              .firstOrNull;
          final cashAccountId =
              cashAccount != null ? cashAccount['id'] as int : null;

          if (cashAccountId != null) {
            await locator<EmployeeRepository>().recordSalaryPayment(
              accountId: accountId,
              cashAccountId: cashAccountId,
              balance: balance,
              balanceType: _balanceType,
              employeeName: _nameController.text,
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'تم تعديل الموظف بنجاح'
                : 'تم إضافة الموظف بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isEditing = widget.employee != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل موظف' : 'إضافة موظف جديد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 20),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + bottomPadding + 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _jobTitleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'المسمى الوظيفي',
                    prefixIcon: Icon(Icons.work),
                  ),
                ),
                const SizedBox(height: 14),

                // العملة
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'العملة',
                    prefixIcon: Icon(Icons.currency_exchange),
                  ),
                  items: _currencyInfo.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                                '${e.value['label']} (${e.value['symbol']})'),
                          ))
                      .toList(),
                  onChanged: isEditing
                      ? null
                      : (v) => setState(() => _currency = v!),
                ),
                const SizedBox(height: 14),

                // الرصيد الافتتاحي + اتجاه الرصيد
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _balanceController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'))
                        ],
                        decoration: InputDecoration(
                          labelText: 'الرصيد الافتتاحي',
                          prefixIcon: const Icon(Icons.calculate),
                          suffixText: AppConstants.currency,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'اتجاه الرصيد الافتتاحي',
                              style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: _balanceType == 'credit'
                                      ? AppColors.success
                                      : AppColors.error),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _balanceType = 'credit'),
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'credit'
                                            ? AppColors.success.withOpacity(0.1)
                                            : Colors.transparent,
                                        borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(9),
                                            bottomRight: Radius.circular(9)),
                                      ),
                                      child: Text(
                                        'له',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'credit'
                                              ? AppColors.success
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _balanceType = 'debit'),
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'debit'
                                            ? AppColors.error.withOpacity(0.1)
                                            : Colors.transparent,
                                        borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(9),
                                            bottomLeft: Radius.circular(9)),
                                      ),
                                      child: Text(
                                        'عليه',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'debit'
                                              ? AppColors.error
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'الملاحظات',
                    prefixIcon: Icon(Icons.edit_note),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 20),
                        label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('إلغاء'),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: bottomPadding),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
