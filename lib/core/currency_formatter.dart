import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat.currency(
    symbol: 'S/',
    decimalDigits: 2,
    customPattern: '¤ #,##0.00',
  );

  /// Formatea cualquier importe a la representación monetaria estándar: ej. "S/ 1,500.00"
  static String format(dynamic amount) {
    if (amount == null) return 'S/ 0.00';
    final double value = (amount is num)
        ? amount.toDouble()
        : (double.tryParse(amount.toString()) ?? 0.0);
    return _formatter.format(value);
  }
}
