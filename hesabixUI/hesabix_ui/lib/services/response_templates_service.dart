import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hesabix_ui/models/response_template.dart';

class ResponseTemplatesService {
  static const String _keyPrefix = 'operator_response_templates_';

  /// Get all saved templates
  static Future<List<ResponseTemplate>> getTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}list';
      final jsonString = prefs.getString(key);

      if (jsonString == null) {
        // Return default templates
        return getDefaultTemplates();
      }

      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((json) => ResponseTemplate.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return getDefaultTemplates();
    }
  }

  /// Save a template
  static Future<void> saveTemplate(ResponseTemplate template) async {
    try {
      final templates = await getTemplates();
      
      // Check if template with same name exists, replace it
      final index = templates.indexWhere((t) => t.name == template.name);
      if (index >= 0) {
        templates[index] = template.copyWith(updatedAt: DateTime.now());
      } else {
        templates.add(template);
      }

      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}list';
      final jsonString = jsonEncode(templates.map((t) => t.toJson()).toList());
      await prefs.setString(key, jsonString);
    } catch (e) {
      // Handle error silently
    }
  }

  /// Delete a template
  static Future<void> deleteTemplate(String templateName) async {
    try {
      final templates = await getTemplates();
      templates.removeWhere((t) => t.name == templateName);

      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}list';
      if (templates.isEmpty) {
        await prefs.remove(key);
      } else {
        final jsonString = jsonEncode(templates.map((t) => t.toJson()).toList());
        await prefs.setString(key, jsonString);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// Get default templates
  static List<ResponseTemplate> getDefaultTemplates() {
    return [
      ResponseTemplate(
        name: 'سلام و تشکر',
        content: 'سلام {user_name}،\n\nبا تشکر از تماس شما. تیم پشتیبانی ما در حال بررسی درخواست شماست و به زودی پاسخ خواهیم داد.\n\nبا احترام',
      ),
      ResponseTemplate(
        name: 'درخواست اطلاعات',
        content: 'سلام {user_name}،\n\nبرای بررسی بهتر درخواست شما، لطفاً اطلاعات زیر را ارسال کنید:\n\n1. جزئیات بیشتر درباره مشکل\n2. تصاویر یا فایل‌های مرتبط (در صورت وجود)\n3. مراحل انجام شده تا کنون\n\nبا تشکر',
      ),
      ResponseTemplate(
        name: 'حل مشکل',
        content: 'سلام {user_name}،\n\nمشکل شما بررسی و حل شد. لطفاً بررسی کنید و در صورت وجود هرگونه مشکل دیگر، اطلاع دهید.\n\nبا تشکر از صبر شما',
      ),
      ResponseTemplate(
        name: 'در انتظار بررسی',
        content: 'سلام {user_name}،\n\nدرخواست شما دریافت شد و در حال بررسی است. به محض اتمام بررسی، با شما تماس خواهیم گرفت.\n\nبا احترام',
      ),
    ];
  }
}



