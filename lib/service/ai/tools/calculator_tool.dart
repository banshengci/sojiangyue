import 'dart:async';
import 'dart:math' as math;

import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:songjiang_reader/service/ai/tools/input/calculator_input.dart';
import 'package:songjiang_reader/utils/log/common.dart';

import 'base_tool.dart';

/// 纯 Dart 算术求值器：支持 + - * / ^ 与括号、一元正负。
/// 不依赖 math_expressions，避免 CI 上包 API 差异导致测试编译失败。
double evaluateArithmetic(String expression) {
  final tokens = _tokenize(expression);
  final parser = _ExprParser(tokens);
  final value = parser.parseExpression();
  if (!parser.isAtEnd) {
    throw FormatException('Unexpected input at index ${parser.index}');
  }
  return value;
}

bool _isDigitOrDot(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || c == '.';
}

List<_Token> _tokenize(String input) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < input.length) {
    final c = input[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    if (c == '+' || c == '-' || c == '*' || c == '/' || c == '^' || c == '(' || c == ')') {
      tokens.add(_Token(_TokenType.op, c));
      i++;
      continue;
    }
    if (_isDigitOrDot(c)) {
      final start = i;
      while (i < input.length && _isDigitOrDot(input[i])) {
        i++;
      }
      final raw = input.substring(start, i);
      final value = double.tryParse(raw);
      if (value == null) {
        throw FormatException('Invalid number: $raw');
      }
      tokens.add(_Token(_TokenType.number, raw, value: value));
      continue;
    }
    throw FormatException('Unsupported character: $c');
  }
  return tokens;
}

enum _TokenType { number, op }

class _Token {
  _Token(this.type, this.raw, {this.value});
  final _TokenType type;
  final String raw;
  final double? value;
}

class _ExprParser {
  _ExprParser(this.tokens);
  final List<_Token> tokens;
  int index = 0;

  bool get isAtEnd => index >= tokens.length;
  _Token get current => tokens[index];

  void _expectOp(String op) {
    if (isAtEnd || current.type != _TokenType.op || current.raw != op) {
      throw FormatException('Expected "$op"');
    }
    index++;
  }

  double parseExpression() {
    var left = parseTerm();
    while (!isAtEnd && current.type == _TokenType.op && (current.raw == '+' || current.raw == '-')) {
      final op = current.raw;
      index++;
      final right = parseTerm();
      left = op == '+' ? left + right : left - right;
    }
    return left;
  }

  double parseTerm() {
    var left = parsePower();
    while (!isAtEnd &&
        current.type == _TokenType.op &&
        (current.raw == '*' || current.raw == '/')) {
      final op = current.raw;
      index++;
      final right = parsePower();
      left = op == '*' ? left * right : left / right;
    }
    return left;
  }

  double parsePower() {
    final base = parseUnary();
    if (!isAtEnd && current.type == _TokenType.op && current.raw == '^') {
      index++;
      final exp = parsePower(); // 右结合
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  double parseUnary() {
    if (!isAtEnd && current.type == _TokenType.op && (current.raw == '-' || current.raw == '+')) {
      final op = current.raw;
      index++;
      final value = parseUnary();
      return op == '-' ? -value : value;
    }
    return parsePrimary();
  }

  double parsePrimary() {
    if (isAtEnd) {
      throw const FormatException('Unexpected end of expression');
    }
    final token = current;
    if (token.type == _TokenType.number) {
      index++;
      return token.value!;
    }
    if (token.type == _TokenType.op && token.raw == '(') {
      index++;
      final value = parseExpression();
      _expectOp(')');
      return value;
    }
    throw FormatException('Unexpected token: ${token.raw}');
  }
}

class CalculatorTool
    extends RepositoryTool<CalculatorInput, Map<String, dynamic>> {
  CalculatorTool()
      : super(
          name: 'calculator',
          description:
              'Evaluate straightforward arithmetic expressions when you need an exact numeric answer. Supports numbers and the operators +, -, *, /, and ^. Returns the original expression along with the computed result as a string.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'expression': {
                'type': 'string',
                'description':
                    'Required. Plain-text arithmetic expression to compute. No variables or functions are supported.',
              },
            },
            'required': ['expression'],
          },
          timeout: const Duration(seconds: 2),
        );

  @override
  CalculatorInput parseInput(Map<String, dynamic> json) {
    return CalculatorInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(CalculatorInput input) async {
    final expression = input.expression?.trim() ?? '';
    if (expression.isEmpty) {
      throw ArgumentError('Expression cannot be empty');
    }

    final result = _evaluateExpression(expression);
    return {
      'expression': expression,
      'result': result,
    };
  }

  @override
  bool shouldLogError(Object error) {
    return error is! TimeoutException;
  }

  String _evaluateExpression(String expression) {
    SjLog.info('Evaluating expression: $expression');
    final evaluation = evaluateArithmetic(expression);
    if (evaluation.isNaN || evaluation.isInfinite) {
      throw FormatException('Expression is not a finite number: $expression');
    }
    final rounded = _roundIfClose(evaluation);
    return rounded.toString();
  }

  double _roundIfClose(double value) {
    const epsilon = 1e-10;
    final rounded = value.roundToDouble();
    return (value - rounded).abs() < epsilon ? rounded : value;
  }
}

final AiToolDefinition calculatorToolDefinition = AiToolDefinition(
  id: 'calculator',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalculatorName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCalculatorDescription,
  build: (context) => CalculatorTool().tool,
);
