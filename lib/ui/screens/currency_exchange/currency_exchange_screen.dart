import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CURRENCY EXCHANGE SCREEN – FirstPro Arabic Accounting App
//  صرافة العملات - تبديل العملات مع القيود المحاسبية
// ═══════════════════════════════════════════════════════════════════════════════

class CurrencyExchangeScreen extends StatefulWidget {
  const CurrencyExchangeScreen({super.key});

  @override
  State<CurrencyExchangeScreen> createState() => _CurrencyExchangeScreenState();
}

class _CurrencyExchangeScreenState extends State<CurrencyExchangeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Form state ────────────────────────────────────────────────────
  String _fromCurrency = 'YER';
  String _toCurrency = 'SAR';
  final _fromAmountController = TextEditingController();
  final _exchangeRateController = TextEditingController();
  final _toAmountController = TextEditingController();
  final _notesController = TextEditingController();
  int? _fromCashBoxId;
  int? _toCashBoxId;
  bool _isRateManual = false;
  bool _isProgrammaticRateUpdate = false;

  // ── Data from DB ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _fromCashBoxes = [];
  List<Map<String, dynamic>> _toCashBoxes = [];
  List<Map<String, dynamic>> _exchanges = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Last exchange result (for journal entry display) ──────────────
  Map<String, dynamic>? _lastExchange;
  bool _showJournalEntry = false;

  // ── Currency display info ─────────────────────────────────────────
  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  // ── Account code offsets per currency ─────────────────────────────
  // ignore: unused_field
  static const Map<String, int> _codeOffset = {'YER': 0, 'SAR': 1, 'USD': 2};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fromAmountController.addListener(_onFromAmountChanged);
    _exchangeRateController.addListener(_onRateChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fromAmountController.dispose();
    _exchangeRateController.dispose();
    _toAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _loadData() async {
    final currencies =
        await locator<ReferenceDataRepository>().getAllCurrencies();
    final exchanges = await locator<CashBoxService>().getAllCurrencyExchanges();

    if (!mounted) return;

    setState(() {
      _currencies = currencies;
      _exchanges = exchanges;
      _isLoading = false;
    });

    await _loadCashBoxes();
    _updateExchangeRate();
  }

  Future<void> _loadCashBoxes() async {
    final fromBoxes =
        await locator<CashBoxService>().getCashBoxesByCurrency(_fromCurrency);
    final toBoxes =
        await locator<CashBoxService>().getCashBoxesByCurrency(_toCurrency);

    if (!mounted) return;

    setState(() {
      _fromCashBoxes = fromBoxes;
      _toCashBoxes = toBoxes;
      // Reset selections if no longer valid
      if (!_fromCashBoxes.any((cb) => cb['id'] == _fromCashBoxId)) {
        _fromCashBoxId = null;
      }
      if (!_toCashBoxes.any((cb) => cb['id'] == _toCashBoxId)) {
        _toCashBoxId = null;
      }
    });
  }

  Future<void> _loadExchanges() async {
    final exchanges = await locator<CashBoxService>().getAllCurrencyExchanges();
    if (!mounted) return;
    setState(() => _exchanges = exchanges);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  EXCHANGE RATE CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Get the exchange_rate value from the currencies table for a given currency code.
  double _getCurrencyRate(String code) {
    for (final c in _currencies) {
      if (c['code'] == code) {
        return (c['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      }
    }
    return 1.0;
  }

  /// Calculate the cross rate: to_amount = from_amount * (from_rate / to_rate)
  double _calculateCrossRate() {
    final fromRate = _getCurrencyRate(_fromCurrency);
    final toRate = _getCurrencyRate(_toCurrency);
    if (toRate == 0) return 0;
    return fromRate / toRate;
  }

  /// Update exchange rate field when currencies change (unless manually edited).
  void _updateExchangeRate() {
    if (_isRateManual) return;
    _isProgrammaticRateUpdate = true;
    final crossRate = _calculateCrossRate();
    _exchangeRateController.text = _formatRate(crossRate);
    _isProgrammaticRateUpdate = false;
    _recalcToAmount();
  }

  /// Recalculate to_amount from from_amount * exchange_rate.
  void _recalcToAmount() {
    final fromAmount = double.tryParse(_fromAmountController.text) ?? 0.0;
    final rate = double.tryParse(_exchangeRateController.text) ?? 0.0;
    final toAmount = fromAmount * rate;
    _toAmountController.text = toAmount == 0 ? '' : _formatAmount(toAmount);
    setState(() {});
  }

  void _onFromAmountChanged() {
    _recalcToAmount();
  }

  void _onRateChanged() {
    // Skip marking as manual when the change is programmatic
    if (_isProgrammaticRateUpdate) {
      _recalcToAmount();
      return;
    }
    // If user edits rate manually, mark as manual
    if (!_isRateManual) {
      _isRateManual = true;
    }
    _recalcToAmount();
  }

  /// Reset rate to auto-calculated value.
  void _resetRateToAuto() {
    setState(() => _isRateManual = false);
    _updateExchangeRate();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  GAIN / LOSS CALCULATION
  // ═══════════════════════════════════════════════════════════════════

  /// Calculate gain/loss based on difference between manual rate and system rate.
  /// Gain/loss is expressed in the TO currency.
  _GainLossResult _calculateGainLoss() {
    final fromAmount = double.tryParse(_fromAmountController.text) ?? 0.0;
    final manualRate = double.tryParse(_exchangeRateController.text) ?? 0.0;
    final systemRate = _calculateCrossRate();

    if (fromAmount == 0 || systemRate == 0) {
      return _GainLossResult(amount: 0, type: 'none');
    }

    final systemToAmount = fromAmount * systemRate;
    final actualToAmount = fromAmount * manualRate;
    final diff = actualToAmount - systemToAmount;

    if ((diff).abs() < 0.01) {
      return _GainLossResult(amount: 0, type: 'none');
    }

    // Convert diff to base currency (YER) for gain/loss accounting
    final toRate = _getCurrencyRate(_toCurrency);
    final diffInBase = diff * toRate;

    if (diff > 0) {
      return _GainLossResult(amount: diffInBase, type: 'gain');
    } else {
      return _GainLossResult(amount: diffInBase.abs(), type: 'loss');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  FORMATTING HELPERS
  // ═══════════════════════════════════════════════════════════════════
  String _formatRate(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _currencySymbol(String code) => _currencyInfo[code]?['symbol'] ?? code;

  String _currencyLabel(String code) =>
      '${_currencyInfo[code]?['label'] ?? code} ($code)';

  // ═══════════════════════════════════════════════════════════════════
  //  EXCHANGE SUBMISSION
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _submitExchange() async {
    // Validation
    if (_fromCurrency == _toCurrency) {
      _showError('يجب اختيار عملتين مختلفتين');
      return;
    }

    final fromAmount = double.tryParse(_fromAmountController.text);
    if (fromAmount == null || fromAmount <= 0) {
      _showError('أدخل مبلغ صالح أكبر من صفر');
      return;
    }

    final exchangeRate = double.tryParse(_exchangeRateController.text);
    if (exchangeRate == null || exchangeRate <= 0) {
      _showError('أدخل سعر صرف صالح أكبر من صفر');
      return;
    }

    if (_fromCashBoxId == null) {
      _showError('اختر صندوق المصدر');
      return;
    }

    if (_toCashBoxId == null) {
      _showError('اختر صندوق الوجهة');
      return;
    }

    // Check cash box balance
    final fromBox = _fromCashBoxes.firstWhere(
      (cb) => cb['id'] == _fromCashBoxId,
      orElse: () => <String, dynamic>{},
    );
    final fromBoxBalance = MoneyHelper.readMoney(fromBox['balance']);
    if (fromAmount > fromBoxBalance) {
      _showError(
          'رصيد الصندوق غير كافي (الرصيد: ${CurrencyFormatter.format(fromBoxBalance)} ${_currencySymbol(_fromCurrency)})');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final toAmount = fromAmount * exchangeRate;
      final gainLoss = _calculateGainLoss();
      final exchangeNumber =
          await locator<CashBoxService>().getNextExchangeNumber();
      final now = DateTime.now().toIso8601String();

      final exchangeMap = <String, dynamic>{
        'exchange_number': exchangeNumber,
        'from_currency': _fromCurrency,
        'to_currency': _toCurrency,
        'from_amount': fromAmount,
        'to_amount': toAmount,
        'exchange_rate': exchangeRate,
        'from_cash_box_id': _fromCashBoxId!,
        'to_cash_box_id': _toCashBoxId!,
        'gain_loss': gainLoss.amount,
        'gain_loss_type': gainLoss.type == 'none' ? null : gainLoss.type,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'created_at': now,
      };

      await locator<CashBoxService>().insertCurrencyExchange(exchangeMap);

      if (!mounted) return;

      // Show success and journal entry
      setState(() {
        _isSaving = false;
        _lastExchange = {
          ...exchangeMap,
          'from_cash_box_name': fromBox['name'] ?? '',
          'to_cash_box_name': _toCashBoxes.firstWhere(
                (cb) => cb['id'] == _toCashBoxId,
                orElse: () => <String, dynamic>{},
              )['name'] ??
              '',
        };
        _showJournalEntry = true;
      });

      // Refresh history and cash boxes (balances changed)
      await _loadExchanges();
      await _loadCashBoxes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت عملية الصرافة بنجاح - $exchangeNumber'),
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
    _fromAmountController.clear();
    _exchangeRateController.clear();
    _toAmountController.clear();
    _notesController.clear();
    setState(() {
      _fromCashBoxId = null;
      _toCashBoxId = null;
      _isRateManual = false;
      _showJournalEntry = false;
      _lastExchange = null;
    });
    _updateExchangeRate();
  }

  /// Swap from/to currencies.
  void _swapCurrencies() {
    setState(() {
      final temp = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = temp;
      _fromCashBoxId = null;
      _toCashBoxId = null;
      _isRateManual = false;
      _fromAmountController.clear();
      _toAmountController.clear();
    });
    _loadCashBoxes();
    _updateExchangeRate();
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
              const Text('صرافة العملات',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.open_in_new, size: 20),
                text: 'صرافة',
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
                  _buildExchangeTab(theme),
                  _buildHistoryTab(theme),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  EXCHANGE TAB
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildExchangeTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Currency Selection Row ──────────────────────────────
          _buildCurrencySelectorRow(theme),
          const SizedBox(height: 16),

          // ── Amount & Rate Section ───────────────────────────────
          _buildAmountSection(theme),
          const SizedBox(height: 16),

          // ── Gain/Loss indicator ─────────────────────────────────
          _buildGainLossIndicator(theme),
          const SizedBox(height: 16),

          // ── Cash Box Selection ──────────────────────────────────
          _buildCashBoxSection(theme),
          const SizedBox(height: 16),

          // ── Notes ───────────────────────────────────────────────
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

          // ── Action Buttons ──────────────────────────────────────
          _buildActionButtons(theme),
          const SizedBox(height: 16),

          // ── Journal Entry Display ───────────────────────────────
          if (_showJournalEntry && _lastExchange != null)
            _buildJournalEntryCard(theme),
        ],
      ),
    );
  }

  // ── Currency Selector Row ──────────────────────────────────────────
  Widget _buildCurrencySelectorRow(ThemeData theme) {
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
            // From Currency
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
                  'من عملة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _buildCurrencyDropdown(
                  value: _fromCurrency,
                  onChanged: (v) {
                    if (v != null && v != _fromCurrency) {
                      if (v == _toCurrency) {
                        // Auto-swap if same
                        setState(() {
                          _toCurrency = _fromCurrency;
                          _fromCurrency = v;
                          _fromCashBoxId = null;
                          _toCashBoxId = null;
                          _isRateManual = false;
                        });
                      } else {
                        setState(() {
                          _fromCurrency = v;
                          _fromCashBoxId = null;
                          _isRateManual = false;
                        });
                      }
                      _loadCashBoxes();
                      _updateExchangeRate();
                    }
                  },
                ),
              ],
            ),

            // Swap Button
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
                    onPressed: _swapCurrencies,
                    icon: Icon(
                      Icons.swap_vert,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    tooltip: 'تبديل العملات',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ),
            ),

            // To Currency
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
                  'إلى عملة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _buildCurrencyDropdown(
                  value: _toCurrency,
                  onChanged: (v) {
                    if (v != null && v != _toCurrency) {
                      if (v == _fromCurrency) {
                        setState(() {
                          _fromCurrency = _toCurrency;
                          _toCurrency = v;
                          _fromCashBoxId = null;
                          _toCashBoxId = null;
                          _isRateManual = false;
                        });
                      } else {
                        setState(() {
                          _toCurrency = v;
                          _toCashBoxId = null;
                          _isRateManual = false;
                        });
                      }
                      _loadCashBoxes();
                      _updateExchangeRate();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyDropdown({
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: _currencies.map((c) {
            final code = c['code'] as String;
            return DropdownMenuItem<String>(
              value: code,
              child: Text(
                _currencyLabel(code),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Amount & Rate Section ──────────────────────────────────────────
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
          children: [
            // From Amount
            Row(
              children: [
                Text(
                  'المبلغ المُرسل',
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
                    _currencySymbol(_fromCurrency),
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
            TextFormField(
              controller: _fromAmountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
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
            const SizedBox(height: 16),

            // Exchange Rate
            Row(
              children: [
                Text(
                  'سعر الصرف',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_isRateManual)
                  InkWell(
                    onTap: _resetRateToAuto,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history,
                            size: 12,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'تلقائي',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_isRateManual)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.flash_on,
                          size: 12,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'تلقائي',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '1 ${_currencySymbol(_fromCurrency)} = ? ${_currencySymbol(_toCurrency)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _exchangeRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'سعر الصرف',
                prefixIcon: const Icon(Icons.show_chart, size: 20),
                suffixIcon: _isRateManual
                    ? IconButton(
                        icon: Icon(
                          Icons.refresh,
                          size: 18,
                          color: AppColors.warning,
                        ),
                        tooltip: 'إعادة للسعر التلقائي',
                        onPressed: _resetRateToAuto,
                      )
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color:
                        _isRateManual ? AppColors.warning : AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Divider with arrow
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_downward,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // To Amount
            Row(
              children: [
                Text(
                  'المبلغ المستلم',
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
                    _currencySymbol(_toCurrency),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calculate,
                    size: 20,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _toAmountController.text.isEmpty
                          ? '0'
                          : _toAmountController.text,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                  Text(
                    _currencySymbol(_toCurrency),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Gain/Loss Indicator ────────────────────────────────────────────
  Widget _buildGainLossIndicator(ThemeData theme) {
    final gainLoss = _calculateGainLoss();
    if (gainLoss.type == 'none') return const SizedBox.shrink();

    final isGain = gainLoss.type == 'gain';
    final color = isGain ? AppColors.success : AppColors.error;
    final icon = isGain ? Icons.trending_up : Icons.trending_down;
    final label = isGain ? 'أرباح صرافة' : 'خسائر صرافة';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            '${CurrencyFormatter.format(gainLoss.amount)} ر.ي',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  // ── Cash Box Selection ─────────────────────────────────────────────
  Widget _buildCashBoxSection(ThemeData theme) {
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
            // From Cash Box
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                Text(
                  'صندوق المصدر',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  _currencySymbol(_fromCurrency),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
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
              items: _fromCashBoxes.map((cb) {
                final id = cb['id'] as int;
                final name = cb['name'] as String;
                final balance = MoneyHelper.readMoney(cb['balance']);
                return DropdownMenuItem<int>(
                  value: id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(balance),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: balance > 0
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _fromCashBoxId = v),
            ),
            const SizedBox(height: 16),

            // To Cash Box
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  'صندوق الوجهة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  _currencySymbol(_toCurrency),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
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
              items: _toCashBoxes.map((cb) {
                final id = cb['id'] as int;
                final name = cb['name'] as String;
                final balance = MoneyHelper.readMoney(cb['balance']);
                return DropdownMenuItem<int>(
                  value: id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(balance),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: balance > 0
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _toCashBoxId = v),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action Buttons ─────────────────────────────────────────────────
  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _submitExchange,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.swap_horiz, size: 20),
            label: Text(
              _isSaving ? 'جاري التنفيذ...' : 'تنفيذ الصرافة',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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
            label: const Text('جديد'),
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

  // ── Journal Entry Card (shown after successful exchange) ───────────
  Widget _buildJournalEntryCard(ThemeData theme) {
    final ex = _lastExchange!;
    final fromAmount = MoneyHelper.readMoney(ex['from_amount']);
    final toAmount = MoneyHelper.readMoney(ex['to_amount']);
    final gainLoss = MoneyHelper.readMoney(ex['gain_loss']);
    final gainLossType = ex['gain_loss_type'] as String?;
    final fromCur = ex['from_currency'] as String;
    final toCur = ex['to_currency'] as String;
    final exchangeNum = ex['exchange_number'] as String? ?? '';

    return Card(
      elevation: 2,
      color: AppColors.primary.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.menu_book,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'القيد المحاسبي',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  exchangeNum,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Table header
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'الحساب',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'مدين',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'دائن',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Debit: Cash&Banks (to_currency) ← receives money
            _journalRow(
              theme,
              account: 'الصناديق والبنوك (${_currencySymbol(toCur)})',
              debit: toAmount,
              credit: 0,
              currency: toCur,
            ),
            const SizedBox(height: 4),

            // Credit: Cash&Banks (from_currency) ← sends money
            _journalRow(
              theme,
              account: 'الصناديق والبنوك (${_currencySymbol(fromCur)})',
              debit: 0,
              credit: fromAmount,
              currency: fromCur,
            ),

            // Gain/Loss row
            if (gainLossType != null && gainLoss > 0) ...[
              const SizedBox(height: 4),
              _journalRow(
                theme,
                account: gainLossType == 'gain' ? 'أرباح صرافة' : 'خسائر صرافة',
                debit: gainLossType == 'loss' ? gainLoss : 0,
                credit: gainLossType == 'gain' ? gainLoss : 0,
                currency: 'YER',
                isGainLoss: true,
                gainLossType: gainLossType,
              ),
            ],

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),

            // Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${CurrencyFormatter.format(fromAmount)} ${_currencySymbol(fromCur)} ← ${CurrencyFormatter.format(toAmount)} ${_currencySymbol(toCur)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _journalRow(
    ThemeData theme, {
    required String account,
    required double debit,
    required double credit,
    required String currency,
    bool isGainLoss = false,
    String? gainLossType,
  }) {
    final rowColor = isGainLoss
        ? (gainLossType == 'gain' ? AppColors.success : AppColors.error)
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: rowColor?.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              account,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: rowColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              debit > 0 ? CurrencyFormatter.format(debit) : '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: debit > 0 ? AppColors.primary : null,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              credit > 0 ? CurrencyFormatter.format(credit) : '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: credit > 0 ? AppColors.error : null,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HISTORY TAB
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildHistoryTab(ThemeData theme) {
    if (_exchanges.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 56,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد عمليات صرافة',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ستظهر هنا عمليات الصرافة السابقة',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadExchanges(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _exchanges.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _buildExchangeCard(theme, _exchanges[index]);
        },
      ),
    );
  }

  Widget _buildExchangeCard(ThemeData theme, Map<String, dynamic> ex) {
    final fromAmount = MoneyHelper.readMoney(ex['from_amount']);
    final toAmount = MoneyHelper.readMoney(ex['to_amount']);
    final rate = (ex['exchange_rate'] as num?)?.toDouble() ?? 0.0;
    final gainLoss = MoneyHelper.readMoney(ex['gain_loss']);
    final gainLossType = ex['gain_loss_type'] as String?;
    final fromCur = ex['from_currency'] as String? ?? '';
    final toCur = ex['to_currency'] as String? ?? '';
    final exchangeNum = ex['exchange_number'] as String? ?? '';
    final createdAt = ex['created_at'] as String? ?? '';
    final fromBoxName = ex['from_cash_box_name'] as String? ?? '';
    final toBoxName = ex['to_cash_box_name'] as String? ?? '';
    final notes = ex['notes'] as String? ?? '';

    // Parse date
    String dateDisplay = '';
    try {
      final dt = DateTime.parse(createdAt);
      dateDisplay =
          '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('CurrencyExchangeScreen._buildExchangeCard: $e');
      dateDisplay = createdAt;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: number + date
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    exchangeNum,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  dateDisplay,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Amount flow
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // From amount
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          CurrencyFormatter.format(fromAmount),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.error,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currencySymbol(fromCur),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow with rate
                  Column(
                    children: [
                      Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatRate(rate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontSize: 10,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),

                  // To amount
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          CurrencyFormatter.format(toAmount),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.success,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currencySymbol(toCur),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Cash box info
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$fromBoxName ← $toBoxName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Gain/Loss badge
            if (gainLossType != null && gainLoss > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (gainLossType == 'gain'
                          ? AppColors.success
                          : AppColors.error)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (gainLossType == 'gain'
                            ? AppColors.success
                            : AppColors.error)
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      gainLossType == 'gain'
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 14,
                      color: gainLossType == 'gain'
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      gainLossType == 'gain' ? 'ربح' : 'خسارة',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: gainLossType == 'gain'
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${CurrencyFormatter.format(gainLoss)} ر.ي',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: gainLossType == 'gain'
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ],

            // Notes
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.sticky_note_2,
                      size: 14, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      notes,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textHint,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  HELPER: Gain/Loss calculation result
// ═══════════════════════════════════════════════════════════════════════════════
class _GainLossResult {
  final double amount;
  final String type; // 'gain', 'loss', or 'none'

  const _GainLossResult({required this.amount, required this.type});
}
