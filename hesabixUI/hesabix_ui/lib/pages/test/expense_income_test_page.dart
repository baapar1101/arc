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
      body: FutureBuilder<CalendarController>(
        future: CalendarController.load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text('خطا در بارگذاری تقویم: ${snapshot.error ?? 'CalendarController'}'),
            );
          }
          return ExpenseIncomeListPage(
            businessId: 1, // ID کسب و کار تست
            calendarController: snapshot.data!,
            authStore: AuthStore(),
            apiClient: ApiClient(),
          );
        },
      ),
    );
  }
}
