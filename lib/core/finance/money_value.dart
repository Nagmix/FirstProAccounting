/// Immutable monetary value represented in the currency's minor units.
///
/// The value is deliberately stored as an integer so financial calculations do
/// not depend on binary floating-point arithmetic. The currency code travels
/// with the amount and is validated by operations that combine values.
class MoneyValue {
  const MoneyValue(this.minorUnits, this.currencyCode)
      : assert(currencyCode != '', 'currencyCode must not be empty');

  final int minorUnits;
  final String currencyCode;

  MoneyValue operator +(MoneyValue other) {
    _checkCurrency(other);
    return MoneyValue(minorUnits + other.minorUnits, currencyCode);
  }

  MoneyValue operator -(MoneyValue other) {
    _checkCurrency(other);
    return MoneyValue(minorUnits - other.minorUnits, currencyCode);
  }

  MoneyValue operator -() => MoneyValue(-minorUnits, currencyCode);

  bool get isZero => minorUnits == 0;

  void _checkCurrency(MoneyValue other) {
    if (currencyCode != other.currencyCode) {
      throw ArgumentError(
        'Cannot combine $currencyCode with ${other.currencyCode}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MoneyValue &&
      other.minorUnits == minorUnits &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => '$minorUnits $currencyCode (minor units)';
}
