import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CASH TRANSFER SCREEN – FirstPro Arabic Accounting App
//  تحويل بين الصناديق - نقل الأموال بين الصناديق مع القيود المحاسبية
// ═══════════════════════════════════════════════════════════════════════════════

class CashTransferScreen extends StatefulWidget {
  const CashTransferScreen({super.key});

  @override
  State<CashTransferScreen> createState() => _CashTransferScreenState();
}

class _CashTransferScreenState extends State<CashTransferScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Form state ────────────────────────────────────────────────────
  String _selectedCurrency = 'YER';
  int? _fromCashBoxId;
  int? _toCashBoxId;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  // ── Data from DB ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  List<Map<String, dynamic>> _transfers = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Last transfer result (for journal entry display) ──────────────
  Map<String, dynamic>? _lastTransfer;
  bool _showJournalEntry = false;

  // ── Currency display info ─────────────────────────────────────────
  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _loadData() async {
    final currencies =
        await locator<ReferenceDataRepository>().getAllCurrencies();
    final transfers = await locator<CashBoxService>().getAllCashTransfers();

    if (!mounted) return;

    setState(() {
      _currencies = currencies;
      _transfers = transfers;
      _isLoading = false;
    });

    await _loadCashBoxes();
  }

  Future<void> _loadCashBoxes() async {
    final boxes = await locator<CashBoxService>()
        .getCashBoxesByCurrency(_selectedCurrency);

    if (!mounted) return;

    setState(() {
      _cashBoxes = boxes;
      // Reset selections if no longer valid
      if (!_cashBoxes.any((cb) => cb['id'] == _fromCashBoxId)) {
        _fromCashBoxId = null;
      }
      if (!_cashBoxes.any((cb) => cb['id'] == _toCashBoxId)) {
        _toCashBoxId = null;
      }
      // Prevent same cash box selection
      if (_fromCashBoxId != null && _fromCashBoxId == _toCashBoxId) {
        _toCashBoxId = null;
      }
    });
  }

  Future<void> _loadTransfers() async {
    final transfers = await locator<CashBoxService>().getAllCashTransfers();
    if (!mounted) return;
    setState(() => _transfers = transfers);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  FORMATTING HELPERS
  // ═══════════════════════════════════════════════════════════════════
  String _currencySymbol(String code) => _currencyInfo[code]?['symbol'] ?? code;

  String _currencyLabel(String code) =>
      '${_currencyInfo[code]?['label'] ?? code} ($code)';

  // ═══════════════════════════════════════════════════════════════════
  //  TRANSFER SUBMISSION
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _submitTransfer() async {
    // Validation
    if (_fromCashBoxId == null) {
      _showError('اختر صندوق المصدر');
      return;
    }

    if (_toCashBoxId == null) {
      _showError('اختر صندوق الوجهة');
      return;
    }

    if (_fromCashBoxId == _toCashBoxId) {
      _showError('لا يمكن التحويل من وإلى نفس الصندوق');
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showError('أدخل مبلغ صالح أكبر من صفر');
      return;
    }

    // Check source cash box balance
    final fromBox = _cashBoxes.firstWhere(
      (cb) => cb['id'] == _fromCashBoxId,
      orElse: () => <String, dynamic>{},
    );
    final fromBoxBalance = MoneyHelper.readMoney(fromBox['balance']);
    if (amount > fromBoxBalance) {
      _showError(
          'رصيد الصندوق غير كافي (الرصيد: ${CurrencyFormatter.format(fromBoxBalance)} ${_currencySymbol(_selectedCurrency)})');
      return;
    }

    final toBox = _cashBoxes.firstWhere(
      (cb) => cb['id'] == _toCashBoxId,
      orElse: () => <String, dynamic>{},
    );

    setState(() => _isSaving = true);

    try {
      final transferNumber =
          await locator<CashBoxService>().getNextTransferNumber();
      final now = DateTime.now().toIso8601String();

      final transferMap = <String, dynamic>{
        'transfer_number': transferNumber,
        'from_cash_box_id': _fromCashBoxId!,
        'to_cash_box_id': _toCashBoxId!,
        'amount': amount,
        'currency': _selectedCurrency,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'created_at': now,
      };

      await locator<CashBoxService>().insertCashTransfer(transferMap);

      if (!mounted) return;

      // Show success and journal entry
      setState(() {
        _isSaving = false;
        _lastTransfer = {
          ...transferMap,
          'from_cash_box_name': fromBox['name'] ?? '',
          'to_cash_box_name': toBox['name'] ?? '',
        };
        _showJournalEntry = true;
      });

      // Refresh history
      await _loadTransfers();
      // Refresh cash boxes (balances changed)
      await _loadCashBoxes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم التحويل بنجاح - $transferNumber'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('حدث خطأ أثناء حفظ العملية');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Reset the form to initial state.
  void _resetForm() {
    _amountController.clear();
    _notesController.clear();
    setState(() {
      _fromCashBoxId = null;
      _toCashBoxId = null;
      _showJournalEntry = false;
      _lastTransfer = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz, size: 22),
              const SizedBox(width: 8),
              const Text('تحويل بين الصناديق',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.open_in_new, size: 20),
                text: 'تحويل',
              ),
              Tab(
                icon: Icon(Icons.history, size: 20),
                text: 'السجل',
              ),
            ],
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildTransferTab(theme),
                  _buildHistoryTab(theme),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  TRANSFER TAB
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTransferTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Currency Selection ────────────────────────────────
          _buildCurrencySelectorCard(theme),
          const SizedBox(height: 16),

          // ── Cash Box Selection ────────────────────────────────
          _buildCashBoxSelectionCard(theme),
          const SizedBox(height: 16),

          // ── Amount Section ────────────────────────────────────
          _buildAmountSection(theme),
          const SizedBox(height: 16),

          // ── Notes ─────────────────────────────────────────────
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: 'ملاحظات',
              hintText: 'أضف ملاحظات على العملية (اختياري)',
              prefixIcon: const Icon(Icons.edit_note),
              alignLabelWithHint: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Action Buttons ────────────────────────────────────
          _buildActionButtons(theme),
          const SizedBox(height: 16),

          // ── Journal Entry Display ─────────────────────────────
          if (_showJournalEntry && _lastTransfer != null)
            _buildJournalEntryCard(theme),
        ],
      ),
    );
  }

  // ── Currency Selector Card ────────────────────────────────────────
  Widget _buildCurrencySelectorCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'العملة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCurrency,
              decoration: InputDecoration(
                hintText: 'اختر العملة',
                prefixIcon: const Icon(Icons.attach_money, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              items: _currencies.map((c) {
                final code = c['code'] as String;
                return DropdownMenuItem<String>(
                  value: code,
                  child: Text(
                    _currencyLabel(code),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null && v != _selectedCurrency) {
                  setState(() {
                    _selectedCurrency = v;
                    _fromCashBoxId = null;
                    _toCashBoxId = null;
                  });
                  _loadCashBoxes();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Cash Box Selection Card ───────────────────────────────────────
  Widget _buildCashBoxSelectionCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── From Cash Box (Source) ───────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_upward,
                    size: 18,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'من صندوق (المصدر)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _currencySymbol(_selectedCurrency),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _fromCashBoxId,
              decoration: InputDecoration(
                hintText: 'اختر صندوق المصدر',
                prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              items: _cashBoxes.map((cb) {
                final id = cb['id'] as int;
                final name = cb['name'] as String;
                final balance = MoneyHelper.readMoney(cb['balance']);
                final isDisabled = id == _toCashBoxId;
                return DropdownMenuItem<int>(
                  value: id,
                  enabled: !isDisabled,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDisabled ? AppColors.textHint : null,
                          ),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(balance),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? AppColors.textHint
                              : AppColors.textSecondary,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _fromCashBoxId = v;
                  // Prevent same selection
                  if (v == _toCashBoxId) {
                    _toCashBoxId = null;
                  }
                });
              },
            ),

            // ── Swap Button ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: IconButton(
                    onPressed: _swapCashBoxes,
                    icon: Icon(
                      Icons.swap_vert,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    tooltip: 'تبديل الصناديق',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ),
            ),

            // ── To Cash Box (Destination) ─────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_downward,
                    size: 18,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'إلى صندوق (الوجهة)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _currencySymbol(_selectedCurrency),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _toCashBoxId,
              decoration: InputDecoration(
                hintText: 'اختر صندوق الوجهة',
                prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              items: _cashBoxes.map((cb) {
                final id = cb['id'] as int;
                final name = cb['name'] as String;
                final balance = MoneyHelper.readMoney(cb['balance']);
                final isDisabled = id == _fromCashBoxId;
                return DropdownMenuItem<int>(
                  value: id,
                  enabled: !isDisabled,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDisabled ? AppColors.textHint : null,
                          ),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(balance),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? AppColors.textHint
                              : AppColors.textSecondary,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _toCashBoxId = v;
                  // Prevent same selection
                  if (v == _fromCashBoxId) {
                    _fromCashBoxId = null;
                  }
                });
              },
            ),

            // ── Same-box warning ─────────────────────────────
            if (_fromCashBoxId != null &&
                _toCashBoxId != null &&
                _fromCashBoxId == _toCashBoxId)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Text(
                        'لا يمكن التحويل من وإلى نفس الصندوق',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
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

  /// Swap from/to cash boxes.
  void _swapCashBoxes() {
    setState(() {
      final temp = _fromCashBoxId;
      _fromCashBoxId = _toCashBoxId;
      _toCashBoxId = temp;
    });
  }

  // ── Amount Section ────────────────────────────────────────────────
  Widget _buildAmountSection(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'مبلغ التحويل',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _currencySymbol(_selectedCurrency),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                hintText: 'أدخل المبلغ',
                prefixIcon: const Icon(Icons.payments, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),

            // ── Source balance display ────────────────────────
            if (_fromCashBoxId != null) ...[
              const SizedBox(height: 12),
              _buildBalanceIndicator(theme),
            ],
          ],
        ),
      ),
    );
  }

  // ── Balance indicator for selected source box ─────────────────────
  Widget _buildBalanceIndicator(ThemeData theme) {
    final fromBox = _cashBoxes.firstWhere(
      (cb) => cb['id'] == _fromCashBoxId,
      orElse: () => <String, dynamic>{},
    );
    final balance = MoneyHelper.readMoney(fromBox['balance']);
    final enteredAmount = double.tryParse(_amountController.text) ?? 0.0;
    final remaining = balance - enteredAmount;
    final isInsufficient = enteredAmount > 0 && remaining < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isInsufficient
            ? AppColors.error.withValues(alpha: 0.06)
            : AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isInsufficient
              ? AppColors.error.withValues(alpha: 0.25)
              : AppColors.info.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isInsufficient ? Icons.warning : Icons.info,
            size: 16,
            color: isInsufficient ? AppColors.error : AppColors.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رصيد الصندوق المصدر: ${CurrencyFormatter.format(balance)} ${_currencySymbol(_selectedCurrency)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isInsufficient ? AppColors.error : AppColors.info,
                  ),
                ),
                if (enteredAmount > 0)
                  Text(
                    isInsufficient
                        ? 'رصيد غير كافي!'
                        : 'المتبقي بعد التحويل: ${CurrencyFormatter.format(remaining)} ${_currencySymbol(_selectedCurrency)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isInsufficient
                          ? AppColors.error
                          : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Buttons ────────────────────────────────────────────────
  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _submitTransfer,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send, size: 20),
            label: Text(_isSaving ? 'جاري التحويل...' : 'تحويل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _resetForm,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('مسح'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Journal Entry Card ────────────────────────────────────────────
  Widget _buildJournalEntryCard(ThemeData theme) {
    final t = _lastTransfer!;
    final amount = MoneyHelper.readMoney(t['amount']);
    final currency = t['currency'] as String? ?? 'YER';
    final fromName = t['from_cash_box_name'] ?? '';
    final toName = t['to_cash_box_name'] ?? '';
    final transferNumber = t['transfer_number'] ?? '';
    final symbol = _currencySymbol(currency);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      color: AppColors.success.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.menu_book,
                    size: 18,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'القيد المحاسبي',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    transferNumber,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Transfer summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'من',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          fromName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Icon(Icons.arrow_back,
                            size: 20, color: AppColors.primary),
                        const SizedBox(height: 2),
                        Text(
                          '${CurrencyFormatter.format(amount)} $symbol',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'إلى',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          toName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Debit entry
            _buildJournalRow(
              theme: theme,
              label: 'مدين',
              description: 'حساب الصناديق والبنوك ($toName) - استلام تحويل',
              amount: amount,
              symbol: symbol,
              isDebit: true,
            ),
            const Divider(height: 24),

            // Credit entry
            _buildJournalRow(
              theme: theme,
              label: 'دائن',
              description: 'حساب الصناديق والبنوك ($fromName) - صرف تحويل',
              amount: amount,
              symbol: symbol,
              isDebit: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJournalRow({
    required ThemeData theme,
    required String label,
    required String description,
    required double amount,
    required String symbol,
    required bool isDebit,
  }) {
    final color = isDebit ? AppColors.primary : AppColors.error;
    final icon = isDebit ? Icons.south_west : Icons.arrow_outward;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${CurrencyFormatter.format(amount)} $symbol',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HISTORY TAB
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildHistoryTab(ThemeData theme) {
    if (_transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_horiz, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text('لا توجد عمليات تحويل', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('ستظهر هنا عمليات التحويل بين الصناديق',
                style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTransfers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _transfers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final t = _transfers[index];
          return _buildTransferHistoryCard(theme, t);
        },
      ),
    );
  }

  Widget _buildTransferHistoryCard(ThemeData theme, Map<String, dynamic> t) {
    final transferNumber = t['transfer_number'] as String? ?? '';
    final fromName = t['from_cash_box_name'] as String? ?? 'غير معروف';
    final toName = t['to_cash_box_name'] as String? ?? 'غير معروف';
    final amount = MoneyHelper.readMoney(t['amount']);
    final currency = t['currency'] as String? ?? 'YER';
    final notes = t['notes'] as String?;
    final createdAt = t['created_at'] as String? ?? '';
    final symbol = _currencySymbol(currency);

    // Parse the date
    String formattedDate = '';
    try {
      if (createdAt.isNotEmpty) {
        final dt = DateTime.parse(createdAt);
        formattedDate =
            '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      debugPrint('CashTransferScreen._buildTransferHistoryCard: $e');
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_horiz,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        transferNumber,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (formattedDate.isNotEmpty)
                  Text(
                    formattedDate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Transfer flow ─────────────────────────────────
            Row(
              children: [
                // From
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_upward,
                              size: 12, color: AppColors.error),
                          const SizedBox(width: 4),
                          Text(
                            'من',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fromName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Arrow + Amount
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Icon(Icons.arrow_back,
                          size: 18, color: AppColors.primary),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${CurrencyFormatter.format(amount)} $symbol',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                ),

                // To
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'إلى',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_downward,
                              size: 12, color: AppColors.success),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        toName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Notes ─────────────────────────────────────────
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_note,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        notes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
