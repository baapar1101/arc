import 'package:flutter/material.dart';
import 'package:hesabix_ui/pages/business/expense_income_list_page.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';

/// صفحه تست برای لیست هزینه و درآمد
class ExpenseIncomeTestPage extends StatelessWidget {
  const ExpenseIncomeTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تست لیست هزینه و درآمد'),
      ),
      body: ExpenseIncomeListPage(
        businessId: 1, // ID کسب و کار تست
        calendarController: CalendarController(),
        authStore: AuthStore(),
        apiClient: ApiClient(),
      ),
    );
  }
}
