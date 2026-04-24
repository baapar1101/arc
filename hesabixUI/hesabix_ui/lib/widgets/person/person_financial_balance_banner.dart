import 'package:flutter/material.dart';
import '../../models/person_model.dart';
import '../../services/person_service.dart';
import '../../utils/number_formatters.dart';

/// مانده و وضعیت مالی شخص؛ برای نمایش فشرده زیر نام داخل همان فیلد انتخاب (بدون عنوان اضافه).
class PersonFinancialBalanceBanner extends StatefulWidget {
  final Person? selectedPerson;

  const PersonFinancialBalanceBanner({
    super.key,
    required this.selectedPerson,
  });

  @override
  State<PersonFinancialBalanceBanner> createState() => _PersonFinancialBalanceBannerState();
}

class _PersonFinancialBalanceBannerState extends State<PersonFinancialBalanceBanner> {
  final PersonService _personService = PersonService();
  Future<Person>? _loadFuture;

  void _prepareLoad() {
    final id = widget.selectedPerson?.id;
    if (id == null) {
      _loadFuture = null;
      return;
    }
    final hint = widget.selectedPerson!;
    if (hint.balance != null && hint.status != null) {
      _loadFuture = Future.value(hint);
      return;
    }
    _loadFuture = _personService.getPerson(id);
  }

  @override
  void initState() {
    super.initState();
    _prepareLoad();
  }

  @override
  void didUpdateWidget(PersonFinancialBalanceBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.selectedPerson?.id;
    final oldId = oldWidget.selectedPerson?.id;
    final bal = widget.selectedPerson?.balance;
    final oldBal = oldWidget.selectedPerson?.balance;
    final st = widget.selectedPerson?.status;
    final oldSt = oldWidget.selectedPerson?.status;
    if (id != oldId || bal != oldBal || st != oldSt) {
      _prepareLoad();
    }
  }

  Color _statusColor(BuildContext context, String? status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'بدهکار':
        return scheme.error;
      case 'بستانکار':
        return scheme.tertiary;
      case 'بالانس':
        return scheme.primary;
      case 'بدون تراکنش':
        return scheme.onSurfaceVariant;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  /// برچسب کوتاه برای نمایش (مثلاً «بالانس» → «تراز»)
  static String statusDisplayLabel(String apiStatus) {
    switch (apiStatus) {
      case 'بالانس':
        return 'تراز';
      default:
        return apiStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.selectedPerson?.id;
    if (id == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final future = _loadFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }

    final nameStyle = theme.textTheme.bodyMedium;
    final balanceFontSize = (nameStyle?.fontSize ?? 14) * 0.85;
    final balanceBaseStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: balanceFontSize,
      height: 1.2,
    );

    return FutureBuilder<Person>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Text(
            '—',
            style: balanceBaseStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        final p = snapshot.data!;
        final balance = p.balance;
        final status = p.status;
        if (balance == null || status == null) {
          return Text(
            '—',
            style: balanceBaseStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }

        final statusColor = _statusColor(context, status);
        final statusLabel = statusDisplayLabel(status);
        final amountText = formatWithThousands(balance);

        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: amountText,
                style: balanceBaseStyle?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(
                text: ' · ',
                style: balanceBaseStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              TextSpan(
                text: statusLabel,
                style: balanceBaseStyle?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
