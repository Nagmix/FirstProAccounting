import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/viewmodels/currency_exchange_viewmodel.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';

/// U-03: Unit tests for CurrencyExchangeViewModel.
///
/// Tests state management and business logic without DB access.
/// The calculation math is tested separately in
/// test/unit/utils/currency_exchange_calculator_test.dart.
void main() {
  late CurrencyExchangeViewModel vm;

  setUp(() {
    vm = CurrencyExchangeViewModel(
      refRepo: _MockRefRepo(),
      cashBoxService: _MockCashBoxService(),
    );
  });

  group('initial state', () {
    test('has correct default values', () {
      expect(vm.fromCurrency, 'YER');
      expect(vm.toCurrency, 'SAR');
      expect(vm.fromAmount, 0.0);
      expect(vm.exchangeRate, 0.0);
      expect(vm.toAmount, 0.0);
      expect(vm.notes, '');
      expect(vm.fromCashBoxId, isNull);
      expect(vm.toCashBoxId, isNull);
      expect(vm.isRateManual, isFalse);
      expect(vm.isLoading, isTrue);
      expect(vm.isSaving, isFalse);
      expect(vm.showJournalEntry, isFalse);
      expect(vm.lastExchange, isNull);
      expect(vm.errorMessage, isNull);
    });
  });

  group('setters notify listeners', () {
    test('setFromCurrency updates state', () {
      var notified = false;
      vm.addListener(() => notified = true);
      vm.setFromCurrency('USD');
      expect(vm.fromCurrency, 'USD');
      expect(notified, isTrue);
    });

    test('setToCurrency updates state', () {
      vm.setToCurrency('EUR');
      expect(vm.toCurrency, 'EUR');
    });

    test('setFromAmount recalculates toAmount', () {
      vm.setExchangeRate(140.0);
      vm.setFromAmount(100.0);
      expect(vm.fromAmount, 100.0);
      expect(vm.toAmount, 14000.0);
    });

    test('setExchangeRate recalculates toAmount', () {
      vm.setFromAmount(50.0);
      vm.setExchangeRate(2.5);
      expect(vm.toAmount, 125.0);
    });

    test('setNotes updates state', () {
      vm.setNotes('test notes');
      expect(vm.notes, 'test notes');
    });

    test('setFromCashBoxId updates state', () {
      vm.setFromCashBoxId(42);
      expect(vm.fromCashBoxId, 42);
    });

    test('setToCashBoxId updates state', () {
      vm.setToCashBoxId(99);
      expect(vm.toCashBoxId, 99);
    });

    test('setRateManual toggles manual mode', () {
      expect(vm.isRateManual, isFalse);
      vm.setRateManual(true);
      expect(vm.isRateManual, isTrue);
    });
  });

  group('swapCurrencies', () {
    test('swaps from/to currencies', () {
      vm.setFromCurrency('USD');
      vm.setToCurrency('SAR');
      vm.swapCurrencies();
      expect(vm.fromCurrency, 'SAR');
      expect(vm.toCurrency, 'USD');
    });

    test('swaps cash box IDs', () {
      vm.setFromCashBoxId(1);
      vm.setToCashBoxId(2);
      vm.swapCurrencies();
      expect(vm.fromCashBoxId, 2);
      expect(vm.toCashBoxId, 1);
    });

    test('resets manual rate mode', () {
      vm.setRateManual(true);
      vm.swapCurrencies();
      expect(vm.isRateManual, isFalse);
    });

    test('notifies listeners', () {
      var notified = false;
      vm.addListener(() => notified = true);
      vm.swapCurrencies();
      expect(notified, isTrue);
    });
  });

  group('resetForm', () {
    test('clears form state', () {
      vm.setFromAmount(1000.0);
      vm.setExchangeRate(140.0);
      vm.setNotes('test');
      vm.setRateManual(true);

      vm.resetForm();

      expect(vm.fromAmount, 0.0);
      expect(vm.toAmount, 0.0);
      expect(vm.notes, '');
      expect(vm.isRateManual, isFalse);
      expect(vm.showJournalEntry, isFalse);
      expect(vm.lastExchange, isNull);
      expect(vm.errorMessage, isNull);
    });

    test('notifies listeners', () {
      var notified = false;
      vm.addListener(() => notified = true);
      vm.resetForm();
      expect(notified, isTrue);
    });
  });

  group('error handling', () {
    test('clearError removes error message', () {
      vm.clearError();
      expect(vm.errorMessage, isNull);
    });
  });

  group('submitExchange validation', () {
    test('rejects zero fromAmount', () async {
      final error = await vm.submitExchange();
      expect(error, isNotNull);
      expect(error, contains('مبلغ'));
    });

    test('rejects missing fromCashBoxId', () async {
      vm.setFromAmount(100.0);
      vm.setExchangeRate(140.0);
      final error = await vm.submitExchange();
      expect(error, isNotNull);
      expect(error, contains('الصندوق المصدر'));
    });

    test('rejects missing toCashBoxId', () async {
      vm.setFromAmount(100.0);
      vm.setExchangeRate(140.0);
      vm.setFromCashBoxId(1);
      final error = await vm.submitExchange();
      expect(error, isNotNull);
      expect(error, contains('الصندوق الهدف'));
    });

    test('rejects same currency', () async {
      vm.setFromAmount(100.0);
      vm.setExchangeRate(1.0);
      vm.setFromCashBoxId(1);
      vm.setToCashBoxId(2);
      vm.setFromCurrency('YER');
      vm.setToCurrency('YER');
      final error = await vm.submitExchange();
      expect(error, contains('نفس العملة'));
    });

    test('rejects same cash box', () async {
      vm.setFromAmount(100.0);
      vm.setExchangeRate(140.0);
      vm.setFromCashBoxId(1);
      vm.setToCashBoxId(1);
      final error = await vm.submitExchange();
      expect(error, contains('نفس الصندوق'));
    });
  });
}

class _MockRefRepo implements ReferenceDataRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockCashBoxService implements CashBoxService {
  @override
  Future<List<Map<String, dynamic>>> getCashBoxesByCurrency(
      String currency) async {
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
