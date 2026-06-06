import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/employee_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/account_repository.dart';
import 'employee_detail_screen.dart';

/// شاشة إدارة الموظفين مع بحث مدمج وفلترة حسب العملة والحالة
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _searchDebounce;
  String? _currencyFilter;
  int _activeFilterIndex = 0; // 0: الكل, 1: نشط, 2: غير نشط

  static const List<String> _currencyOptions = ['الكل', 'YER', 'SAR', 'USD'];
  static const List<String> _activeOptions = ['الكل', 'نشط', 'غير نشط'];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await locator<ReferenceDataRepository>().getAllEmployees();
      if (mounted) {
        setState(() {
          _employees = employees;
          _filteredEmployees = employees;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _applyFilters() {
    var filtered = _employees.toList();

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        final phone = (e['phone'] as String? ?? '').toLowerCase();
        final jobTitle = (e['job_title'] as String? ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q) || jobTitle.contains(q);
      }).toList();
    }

    // Currency filter
    if (_currencyFilter != null && _currencyFilter!.isNotEmpty) {
      filtered = filtered.where((e) => e['currency'] == _currencyFilter).toList();
    }

    // Active/Inactive filter
    if (_activeFilterIndex == 1) {
      filtered = filtered.where((e) => (e['is_active'] as int?) == 1).toList();
    } else if (_activeFilterIndex == 2) {
      filtered = filtered.where((e) => (e['is_active'] as int?) != 1).toList();
    }

    setState(() => _filteredEmployees = filtered);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = query;
      _applyFilters();
    });
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفين'),
      ),
      body: Column(
        children: [
          // ── Search Bar ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الهاتف أو المسمى الوظيفي...',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchQuery = '';
                          _applyFilters();
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
            ),
          ),

          // ── Filter Chips Row ───────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: Row(
              children: [
                // Active/Inactive filter
                Expanded(
                  child: Row(
                    children: List.generate(_activeOptions.length, (i) {
                      final isSelected = _activeFilterIndex == i;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(_activeOptions[i], style: TextStyle(fontSize: 12)),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _activeFilterIndex = i);
                            _applyFilters();
                          },
                          labelStyle: TextStyle(
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                          ),
                          backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                          selectedColor: AppColors.primary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                // Currency filter dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: _currencyFilter ?? 'الكل',
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    iconSize: 18,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                    items: _currencyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) {
                      setState(() {
                        _currencyFilter = (v == null || v == 'الكل') ? null : v;
                      });
                      _applyFilters();
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Employee Count ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: Row(
              children: [
                Text(
                  'عدد الموظفين: ${_filteredEmployees.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Employee List ──────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEmployees.isEmpty
                    ? _buildEmptyState(theme, isDark)
                    : RefreshIndicator(
                        onRefresh: _loadEmployees,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredEmployees.length,
                          itemBuilder: (context, index) {
                            return _buildEmployeeCard(_filteredEmployees[index], theme, isDark);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmployeeSheet(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('لا يوجد موظفين بعد', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
          const SizedBox(height: 8),
          Text('اضغط على + لإضافة موظف جديد', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> employee, ThemeData theme, bool isDark) {
    final name = employee['name'] as String? ?? '';
    final phone = employee['phone'] as String? ?? '';
    final jobTitle = employee['job_title'] as String? ?? '';
    final balance = MoneyHelper.readMoney(employee['balance']);
    final balanceType = employee['balance_type'] as String? ?? 'credit';
    final currency = employee['currency'] as String? ?? 'YER';
    final isActive = (employee['is_active'] as int?) == 1;
    final isCredit = balanceType == 'credit';
    final currencySymbol = _currencySymbol(currency);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? (isDark ? AppColors.darkBorder : AppColors.border)
              : AppColors.error.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(employee),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name + details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('غير نشط', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error, fontSize: 10)),
                          ),
                      ],
                    ),
                    if (jobTitle.isNotEmpty || phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [jobTitle, phone].where((s) => s.isNotEmpty).join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (balance > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isCredit ? AppColors.success : AppColors.error).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  CurrencyFormatter.formatValue(balance),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isCredit ? AppColors.success : AppColors.error,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${isCredit ? 'له' : 'عليه'} $currencySymbol',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isCredit ? AppColors.success : AppColors.error,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Arrow
              Icon(Icons.chevron_left, color: AppColors.textHint, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToDetail(Map<String, dynamic> employee) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeDetailScreen(employee: employee),
      ),
    ).then((_) => _loadEmployees());
  }

  void _showAddEmployeeSheet({Map<String, dynamic>? employee}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEmployeeScreen(employee: employee),
        fullscreenDialog: true,
      ),
    ).then((result) {
      if (result == true) _loadEmployees();
    });
  }
}

/// شاشة إضافة/تعديل موظف - بيانات بسيطة
class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key, this.employee});

  final Map<String, dynamic>? employee;

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _balanceController = TextEditingController();
  final _notesController = TextEditingController();

  String _balanceType = 'credit'; // له
  String _currency = 'YER';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      final e = widget.employee!;
      _nameController.text = e['name'] as String? ?? '';
      _phoneController.text = e['phone'] as String? ?? '';
      _jobTitleController.text = e['job_title'] as String? ?? '';
      _balanceController.text = MoneyHelper.readMoney(e['balance']).toStringAsFixed(2);
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

    final now = DateTime.now().toIso8601String();
    final balance = double.tryParse(_balanceController.text) ?? 0.0;

    // Get the employee account for this currency
    int? accountId;
    final accounts = await locator<AccountRepository>().getAccountsByCurrency(_currency);
    int accountCodeSuffix = _currency == 'YER' ? 5100 : (_currency == 'SAR' ? 5101 : 5102);
    final empAccount = accounts.where((a) => a['account_code'] == accountCodeSuffix.toString()).firstOrNull;
    if (empAccount != null) {
      accountId = empAccount['id'] as int;
    }

    final data = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'job_title': _jobTitleController.text.trim().isEmpty ? null : _jobTitleController.text.trim(),
      'balance': balance,
      'balance_type': _balanceType,
      'currency': _currency,
      'account_id': accountId,
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'is_active': 1,
      'updated_at': now,
    };

    if (widget.employee != null) {
      await locator<ReferenceDataRepository>().updateEmployee(widget.employee!['id'] as int, data);
    } else {
      data['created_at'] = now;
      await locator<ReferenceDataRepository>().insertEmployee(data);

      // If opening balance > 0, post journal entry
      if (balance > 0 && accountId != null) {
        int cashCodeSuffix = _currency == 'YER' ? 1100 : (_currency == 'SAR' ? 1101 : 1102);
        final cashAccount = accounts.where((a) => a['account_code'] == cashCodeSuffix.toString()).firstOrNull;
        final cashAccountId = cashAccount != null ? cashAccount['id'] as int : null;

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
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.employee != null ? 'تم تعديل الموظف بنجاح' : 'تم إضافة الموظف بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  String _currencySymbol() {
    switch (_currency) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      default: return 'ر.ي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.employee != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل موظف' : 'إضافة موظف جديد'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 20),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.person_add, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'تعديل بيانات الموظف' : 'موظف جديد',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isEditing ? 'قم بتعديل البيانات المطلوبة' : 'أدخل بيانات الموظف الجديد',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // الاسم
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'الاسم *',
                  prefixIcon: const Icon(Icons.person),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // الهاتف + المسمى الوظيفي
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        prefixIcon: const Icon(Icons.phone),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _jobTitleController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'المسمى الوظيفي',
                        prefixIcon: const Icon(Icons.work),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // العملة
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(
                  labelText: 'العملة',
                  prefixIcon: const Icon(Icons.monetization_on),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'YER', child: Text('ريال يمني (ر.ي)')),
                  DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي (ر.س)')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (\$)')),
                ],
                onChanged: isEditing ? null : (v) => setState(() => _currency = v!),
              ),
              const SizedBox(height: 14),

              // الرصيد الافتتاحي مع له/عليه
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _balanceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'الرصيد الافتتاحي',
                        prefixIcon: const Icon(Icons.calculate),
                        suffixText: _currencySymbol(),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
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
                          child: Text('الحالة', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: _balanceType == 'credit' ? AppColors.success : AppColors.error),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _balanceType = 'credit'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _balanceType == 'credit' ? AppColors.success.withOpacity(0.1) : Colors.transparent,
                                      borderRadius: const BorderRadius.only(topRight: Radius.circular(9), bottomRight: Radius.circular(9)),
                                    ),
                                    child: Text(
                                      'له',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _balanceType == 'credit' ? AppColors.success : AppColors.textHint,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _balanceType = 'debit'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _balanceType == 'debit' ? AppColors.error.withOpacity(0.1) : Colors.transparent,
                                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(9), bottomLeft: Radius.circular(9)),
                                    ),
                                    child: Text(
                                      'عليه',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _balanceType == 'debit' ? AppColors.error : AppColors.textHint,
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

              // ملاحظات
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'ملاحظات',
                  prefixIcon: const Icon(Icons.edit_note),
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // أزرار الحفظ
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 20),
                      label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('إلغاء'),
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
}
