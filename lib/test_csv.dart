import 'package:csv/csv.dart';

void main() {
  List<List<dynamic>> rows = [
    ['a', 'b', 'c'],
    [1, 2, 3]
  ];
  String encoded = csv.encode(rows);
  print(encoded);
}
