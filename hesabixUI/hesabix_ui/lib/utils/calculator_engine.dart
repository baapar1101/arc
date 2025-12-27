/// موتور محاسباتی امن برای ارزیابی عبارات ریاضی
class CalculatorEngine {
  /// ارزیابی یک عبارت ریاضی
  /// 
  /// پشتیبانی از: +, -, *, /, %, ( )
  /// 
  /// مثال: "2 + 3 * 4" => 14
  /// 
  /// در صورت خطا، null برمی‌گرداند
  static double? evaluate(String expression) {
    try {
      // حذف فاصله‌ها
      expression = expression.replaceAll(' ', '');
      
      if (expression.isEmpty) return null;
      
      // بررسی وجود کاراکترهای غیرمجاز
      final validChars = RegExp(r'^[0-9+\-*/().%]+$');
      if (!validChars.hasMatch(expression)) {
        return null;
      }
      
      // تبدیل به فرمت قابل پردازش
      final tokens = _tokenize(expression);
      if (tokens.isEmpty) return null;
      
      // ارزیابی با استفاده از Shunting Yard Algorithm
      return _evaluateExpression(tokens);
    } catch (e) {
      return null;
    }
  }
  
  /// تبدیل رشته به توکن‌ها
  static List<String> _tokenize(String expression) {
    final List<String> tokens = [];
    String currentNumber = '';
    
    for (int i = 0; i < expression.length; i++) {
      final char = expression[i];
      
      if (RegExp(r'[0-9.]').hasMatch(char)) {
        currentNumber += char;
      } else {
        if (currentNumber.isNotEmpty) {
          tokens.add(currentNumber);
          currentNumber = '';
        }
        
        if (char == '-' && (tokens.isEmpty || 
            ['+', '-', '*', '/', '(', '%'].contains(tokens.last))) {
          // عدد منفی
          currentNumber = '-';
        } else {
          tokens.add(char);
        }
      }
    }
    
    if (currentNumber.isNotEmpty) {
      tokens.add(currentNumber);
    }
    
    return tokens;
  }
  
  /// ارزیابی عبارت با استفاده از Shunting Yard Algorithm
  static double? _evaluateExpression(List<String> tokens) {
    try {
      final List<double> values = [];
      final List<String> operators = [];
      
      for (int i = 0; i < tokens.length; i++) {
        final token = tokens[i];
        
        if (_isNumber(token)) {
          final num = double.tryParse(token);
          if (num == null) return null;
          values.add(num);
        } else if (token == '(') {
          operators.add(token);
        } else if (token == ')') {
          while (operators.isNotEmpty && operators.last != '(') {
            if (!_applyOperator(values, operators)) return null;
          }
          if (operators.isEmpty) return null;
          operators.removeLast(); // حذف '('
        } else if (_isOperator(token)) {
          while (operators.isNotEmpty &&
                 operators.last != '(' &&
                 _getPrecedence(operators.last) >= _getPrecedence(token)) {
            if (!_applyOperator(values, operators)) return null;
          }
          operators.add(token);
        }
      }
      
      while (operators.isNotEmpty) {
        if (!_applyOperator(values, operators)) return null;
      }
      
      if (values.length != 1) return null;
      return values.first;
    } catch (e) {
      return null;
    }
  }
  
  /// اعمال عملگر
  static bool _applyOperator(List<double> values, List<String> operators) {
    if (operators.isEmpty || values.length < 2) return false;
    
    final op = operators.removeLast();
    final b = values.removeLast();
    final a = values.removeLast();
    
    double? result;
    
    switch (op) {
      case '+':
        result = a + b;
        break;
      case '-':
        result = a - b;
        break;
      case '*':
        result = a * b;
        break;
      case '/':
        if (b == 0) return false; // تقسیم بر صفر
        result = a / b;
        break;
      case '%':
        if (b == 0) return false;
        result = a % b;
        break;
      default:
        return false;
    }
    
    values.add(result);
    return true;
  }
  
  /// بررسی اینکه آیا توکن یک عدد است
  static bool _isNumber(String token) {
    return RegExp(r'^-?[0-9]+\.?[0-9]*$').hasMatch(token);
  }
  
  /// بررسی اینکه آیا توکن یک عملگر است
  static bool _isOperator(String token) {
    return ['+', '-', '*', '/', '%'].contains(token);
  }
  
  /// اولویت عملگرها
  static int _getPrecedence(String op) {
    switch (op) {
      case '+':
      case '-':
        return 1;
      case '*':
      case '/':
      case '%':
        return 2;
      default:
        return 0;
    }
  }
  
  /// فرمت کردن عدد برای نمایش
  /// حذف صفرهای اضافی در اعشار
  static String formatNumber(double number) {
    if (number == number.toInt()) {
      return number.toInt().toString();
    }
    
    // حذف صفرهای اضافی
    String formatted = number.toString();
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    
    return formatted;
  }
  
  /// فرمت کردن عدد با جداکننده هزارگان
  static String formatNumberWithSeparator(double number) {
    final formatted = formatNumber(number);
    
    // اگر عدد اعشاری است، فقط قسمت صحیح را فرمت کن
    if (formatted.contains('.')) {
      final parts = formatted.split('.');
      final integerPart = _addThousandSeparator(parts[0]);
      return '$integerPart.${parts[1]}';
    }
    
    return _addThousandSeparator(formatted);
  }
  
  /// اضافه کردن جداکننده هزارگان
  static String _addThousandSeparator(String number) {
    final isNegative = number.startsWith('-');
    if (isNegative) {
      number = number.substring(1);
    }
    
    final regex = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = number.replaceAllMapped(regex, (match) => '${match[1]},');
    
    return isNegative ? '-$formatted' : formatted;
  }
}

