import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/ai/tools/calculator_tool.dart';

void main() {
  group('evaluateArithmetic', () {
    test('basic ops', () {
      expect(evaluateArithmetic('1 + 2'), 3);
      expect(evaluateArithmetic('3 * 4'), 12);
      expect(evaluateArithmetic('10 / 4'), 2.5);
      expect(evaluateArithmetic('2 ^ 3'), 8);
    });

    test('unary and parentheses', () {
      expect(evaluateArithmetic('-5 + 3'), -2);
      expect(evaluateArithmetic('(1 + 2) * 3'), 9);
      expect(evaluateArithmetic('2 ^ (1 + 1)'), 4);
    });

    test('invalid throws', () {
      expect(() => evaluateArithmetic('1 +'), throwsFormatException);
      expect(() => evaluateArithmetic('1 + x'), throwsFormatException);
    });
  });
}
