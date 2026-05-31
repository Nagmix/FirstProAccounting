import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/employee_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/account_repository.dart';

/// شاشة إدارة الموظفين مع رصيد افتتاحي وربط بدليل الحسابات
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = true;
  String _searchQuery = ''; // Used in filter

  @override
  void initState() {
    super.initState();
    _loadEmployees();
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

  void _filterEmployees(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredEmployees = _employees;
      } else {
        _filteredEmployees = _employees.where((e) {
          final name = (e['name'] as String? ?? '').toLowerCase();
          final phone = (e['phone'] as String? ?? '').toLowerCase();
          final jobTitle = (e['job_title'] as String? ?? '').toLowerCase();
          final q = query.toLowerCase();
          return name.contains(q) || phone.contains(q) || jobTitle.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: _isLoading
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
    final currencySymbol = currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: InkWell(
        onTap: () => _showEmployeeActions(employee),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.person,
                  color: AppColors.primary,
                  size: 24,
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
                  ],
                ),
              ),

              // Balance
              if (balance > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isCredit ? AppColors.success : AppColors.error).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(balance),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isCredit ? AppColors.success : AppColors.error,
                        ),
                      ),
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
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بحث عن موظف'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'اسم الموظف أو الهاتف...',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _filterEmployees,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _filterEmployees('');
            },
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _showEmployeeActions(Map<String, dynamic> employee) {
    final isActive = (employee['is_active'] as int?) == 1;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddEmployeeSheet(employee: employee);
              },
            ),
            ListTile(
              leading: Icon(
                isActive ? Icons.block : Icons.check_circle,
                color: isActive ? AppColors.warning : AppColors.success,
              ),
              title: Text(isActive ? 'تعطيل' : 'تفعيل'),
              onTap: () async {
                Navigator.pop(ctx);
                await locator<ReferenceDataRepository>().updateEmployee(employee['id'] as int, {
                  'is_active': isActive ? 0 : 1,
                  'updated_at': DateTime.now().toIso8601String(),
                });
                _loadEmployees();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('حذف', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    title: const Text('تأكيد الحذف'),
                    content: Text('هل أنت متأكد من حذف الموظف "${employee['name']}"؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('إلغاء')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                        onPressed: () => Navigator.pop(ctx2, true),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await locator<ReferenceDataRepository>().deleteEmployee(employee['id'] as int);
                  _loadEmployees();
                }
              },
            ),
          ],
        ),
      ),
    );
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
    // Try to find account code like 5100/5101/5102 based on currency
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
        // Get cash box account for this currency
        int cashCodeSuffix = _currency == 'YER' ? 1100 : (_currency == 'SAR' ? 1101 : 1102);
        final cashAccount = accounts.where((a) => a['account_code'] == cashCodeSuffix.toString()).firstOrNull;
        final cashAccountId = cashAccount != null ? cashAccount['id'] as int : null;

        if (_balanceType == 'credit') {
          // له - الموظف له رصيد: مدين = الموظف، دائن = الصندوق
          if (cashAccountId != null) {
            await locator<EmployeeRepository>().recordSalaryPayment(
              accountId: accountId,
              cashAccountId: cashAccountId,
              balance: balance,
              balanceType: 'credit',
              employeeName: _nameController.text,
            );
          }
        } else {
          // عليه - الموظف عليه رصيد: مدين = الصندوق، دائن = الموظف
          if (cashAccountId != null) {
            await locator<EmployeeRepository>().recordSalaryPayment(
              accountId: accountId,
              cashAccountId: cashAccountId,
              balance: balance,
              balanceType: 'debit',
              employeeName: _nameController.text,
            );
          }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.employee != null;
    final currencySymbol = _currency == 'SAR' ? 'ر.س' : (_currency == 'USD' ? r'$' : 'ر.ي');

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
              // الاسم
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  prefixIcon: Icon(Icons.person),
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
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _jobTitleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'المسمى الوظيفي',
                        prefixIcon: Icon(Icons.work),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // العملة
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: const InputDecoration(
                  labelText: 'العملة',
                  prefixIcon: Icon(Icons.monetization_on),
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
                        suffixText: currencySymbol,
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
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  prefixIcon: Icon(Icons.edit_note),
                  alignLabelWithHint: true,
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
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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
