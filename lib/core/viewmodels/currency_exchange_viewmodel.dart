import 'package:flutter/foundation.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/utils/currency_exchange_calculator.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';

/// U-03: ViewModel for CurrencyExchangeScreen.
///
/// Extracts all state management and business logic from the screen,
/// leaving only UI rendering + TextEditingController plumbing in the
/// StatefulWidget. The ViewModel is a ChangeNotifier registered as a
/// factory in service_locator.dart (fresh instance per screen).
///
/// State managed:
///   - fromCurrency, toCurrency, fromAmount, exchangeRate, toAmount.
///   - fromCashBoxId, toCashBoxId.
///   - currencies list, fromCashBoxes, toCashBoxes, exchanges history.
///   - isLoading, isSaving, isRateManual.
///   - lastExchange (for journal entry display), showJournalEntry.
///   - errorMessage.
///
/// Business logic:
///   - loadData(): loads currencies + cash boxes + exchange history.
///   - updateExchangeRate(): auto-calculates cross rate (unless manual).
///   - recalcToAmount(): recalculates to_amount from from * rate.
///   - swapCurrencies(): swaps from/to and recalculates.
///   - submitExchange(): validates + saves via CashBoxService.
///   - resetForm(): clears form for next exchange.
///
/// Calculation logic delegates to CurrencyExchangeCalculator (pure class).
class CurrencyExchangeViewModel extends ChangeNotifier {
  final ReferenceDataRepository _refRepo;
  final CashBoxService _cashBoxService;

  CurrencyExchangeViewModel({
    ReferenceDataRepository? refRepo,
    CashBoxService? cashBoxService,
  })  : _refRepo = refRepo ?? locator<ReferenceDataRepository>(),
        _cashBoxService = cashBoxService ?? locator<CashBoxService>();

  // ── Form state ────────────────────────────────────────────────────
  String _fromCurrency = 'YER';
  String _toCurrency = 'SAR';
  double _fromAmount = 0.0;
  double _exchangeRate = 0.0;
  double _toAmount = 0.0;
  String _notes = '';
  int? _fromCashBoxId;
  int? _toCashBoxId;
  bool _isRateManual = false;

  // ── Data from DB ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _fromCashBoxes = [];
  List<Map<String, dynamic>> _toCashBoxes = [];
  List<Map<String, dynamic>> _exchanges = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Last exchange result ──────────────────────────────────────────
  Map<String, dynamic>? _lastExchange;
  bool _showJournalEntry = false;

  // ── Error ─────────────────────────────────────────────────────────
  String? _errorMessage;

  // ── Getters ───────────────────────────────────────────────────────
  String get fromCurrency => _fromCurrency;
  String get toCurrency => _toCurrency;
  double get fromAmount => _fromAmount;
  double get exchangeRate => _exchangeRate;
  double get toAmount => _toAmount;
  String get notes => _notes;
  int? get fromCashBoxId => _fromCashBoxId;
  int? get toCashBoxId => _toCashBoxId;
  bool get isRateManual => _isRateManual;

  List<Map<String, dynamic>> get currencies => _currencies;
  List<Map<String, dynamic>> get fromCashBoxes => _fromCashBoxes;
  List<Map<String, dynamic>> get toCashBoxes => _toCashBoxes;
  List<Map<String, dynamic>> get exchanges => _exchanges;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  Map<String, dynamic>? get lastExchange => _lastExchange;
  bool get showJournalEntry => _showJournalEntry;
  String? get errorMessage => _errorMessage;

  /// The system (auto) cross rate — fromRate / toRate.
  double get systemCrossRate =>
      CurrencyExchangeCalculator.calculateCrossRateFromCurrencies(
        currencies: _currencies,
        fromCurrency: _fromCurrency,
        toCurrency: _toCurrency,
      );

  /// Gain/loss result for the current form state.
  GainLossResult get gainLoss =>
      CurrencyExchangeCalculator.calculateGainLoss(
        fromAmount: _fromAmount,
        manualRate: _exchangeRate,
        systemRate: systemCrossRate,
        toCurrencyRateToBase:
            CurrencyExchangeCalculator.getCurrencyRate(_currencies, _toCurrency),
      );

  // ── Setters (with notifyListeners) ────────────────────────────────

  void setFromCurrency(String value) {
    _fromCurrency = value;
    _errorMessage = null;
    notifyListeners();
  }

  void setToCurrency(String value) {
    _toCurrency = value;
    _errorMessage = null;
    notifyListeners();
  }

  void setFromAmount(double value) {
    _fromAmount = value;
    _recalcToAmount();
    notifyListeners();
  }

  void setExchangeRate(double value) {
    _exchangeRate = value;
    _recalcToAmount();
    notifyListeners();
  }

  void setNotes(String value) {
    _notes = value;
    notifyListeners();
  }

  void setFromCashBoxId(int? value) {
    _fromCashBoxId = value;
    notifyListeners();
  }

  void setToCashBoxId(int? value) {
    _toCashBoxId = value;
    notifyListeners();
  }

  void setRateManual(bool value) {
    _isRateManual = value;
    notifyListeners();
  }

  // ── Data loading ──────────────────────────────────────────────────

  Future<void> loadData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _currencies = await _refRepo.getAllCurrencies();
      _exchanges = await _cashBoxService.getAllCurrencyExchanges();
      await _loadCashBoxes();
      _updateExchangeRate();
    } catch (e) {
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات: $e';
      if (kDebugMode) debugPrint('CurrencyExchangeViewModel.loadData: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadCashBoxes() async {
    _fromCashBoxes =
        await _cashBoxService.getCashBoxesByCurrency(_fromCurrency);
    _toCashBoxes = await _cashBoxService.getCashBoxesByCurrency(_toCurrency);
  }

  Future<void> reloadCashBoxes() async {
    await _loadCashBoxes();
    notifyListeners();
  }

  // ── Rate calculation ──────────────────────────────────────────────

  /// Update exchange rate from system cross rate (unless manual).
  void updateExchangeRate() {
    if (_isRateManual) return;
    _updateExchangeRate();
    notifyListeners();
  }

  void _updateExchangeRate() {
    if (_isRateManual) return;
    final crossRate = systemCrossRate;
    _exchangeRate = crossRate;
    _recalcToAmount();
  }

  void _recalcToAmount() {
    _toAmount =
        CurrencyExchangeCalculator.calculateToAmount(_fromAmount, _exchangeRate);
  }

  /// Reset rate to auto-calculated value.
  void resetRateToAuto() {
    _isRateManual = false;
    _updateExchangeRate();
    notifyListeners();
  }

  // ── Swap currencies ───────────────────────────────────────────────

  void swapCurrencies() {
    final temp = _fromCurrency;
    _fromCurrency = _toCurrency;
    _toCurrency = temp;

    final tempBox = _fromCashBoxId;
    _fromCashBoxId = _toCashBoxId;
    _toCashBoxId = tempBox;

    _isRateManual = false;
    _loadCashBoxes();
    _updateExchangeRate();
    notifyListeners();
  }

  // ── Submit exchange ───────────────────────────────────────────────

  /// Validate and submit the exchange. Returns null on success, or an
  /// error message string on validation failure.
  Future<String?> submitExchange() async {
    // Validation
    if (_fromAmount <= 0) return 'يرجى إدخال مبلغ أكبر من صفر';
    if (_exchangeRate <= 0) return 'يرجى إدخال سعر صرف صحيح';
    if (_fromCashBoxId == null) return 'يرجى اختيار الصندوق المصدر';
    if (_toCashBoxId == null) return 'يرجى اختيار الصندوق الهدف';
    if (_fromCurrency == _toCurrency) return 'لا يمكن صرافة نفس العملة';
    if (_fromCashBoxId == _toCashBoxId) return 'لا يمكن استخدام نفس الصندوق';

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final gainLossResult = gainLoss;
      final exchangeNumber =
          await _cashBoxService.getNextExchangeNumber();
      final now = DateTime.now().toIso8601String();

      final exchangeMap = <String, dynamic>{
        'exchange_number': exchangeNumber,
        'from_currency': _fromCurrency,
        'to_currency': _toCurrency,
        'from_amount': _fromAmount,
        'to_amount': _toAmount,
        'exchange_rate': _exchangeRate,
        'from_cash_box_id': _fromCashBoxId!,
        'to_cash_box_id': _toCashBoxId!,
        'gain_loss': gainLossResult.amount,
        'gain_loss_type': gainLossResult.isNone
            ? null
            : (gainLossResult.isGain ? 'gain' : 'loss'),
        'notes': _notes.trim().isEmpty ? null : _notes.trim(),
        'created_at': now,
      };

      await _cashBoxService.insertCurrencyExchange(exchangeMap);

      _lastExchange = exchangeMap;
      _showJournalEntry = true;

      // Reload history
      _exchanges = await _cashBoxService.getAllCurrencyExchanges();

      _isSaving = false;
      notifyListeners();
      return null; // success
    } catch (e) {
      _isSaving = false;
      _errorMessage = 'فشل حفظ العملية: $e';
      if (kDebugMode) debugPrint('CurrencyExchangeViewModel.submitExchange: $e');
      notifyListeners();
      return _errorMessage;
    }
  }

  // ── Reset form ────────────────────────────────────────────────────

  void resetForm() {
    _fromAmount = 0.0;
    _exchangeRate = 0.0;
    _toAmount = 0.0;
    _notes = '';
    _isRateManual = false;
    _lastExchange = null;
    _showJournalEntry = false;
    _errorMessage = null;
    _updateExchangeRate();
    notifyListeners();
  }

  // ── Clear error ───────────────────────────────────────────────────

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
