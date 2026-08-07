import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// رنگ آواتار پایدار از روی نام کسب‌وکار.
Color businessAvatarColor(String name, ColorScheme scheme) {
  if (name.trim().isEmpty) return scheme.primary;
  const hues = [215.0, 168.0, 278.0, 28.0, 338.0, 128.0, 48.0, 190.0];
  final index = name.hashCode.abs() % hues.length;
  return HSLColor.fromAHSL(1, hues[index], 0.52, 0.48).toColor();
}

String businessAvatarInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed[0].toUpperCase();
}

String translateBusinessType(String type, AppLocalizations l10n) {
  switch (type) {
    case 'شرکت':
      return l10n.company;
    case 'مغازه':
      return l10n.shop;
    case 'فروشگاه':
      return l10n.store;
    case 'اتحادیه':
      return l10n.union;
    case 'باشگاه':
      return l10n.club;
    case 'موسسه':
      return l10n.institute;
    case 'شخصی':
      return l10n.individual;
    default:
      return type;
  }
}

String translateBusinessField(String field, AppLocalizations l10n) {
  switch (field) {
    case 'تولیدی':
      return l10n.manufacturing;
    case 'بازرگانی':
      return l10n.trading;
    case 'خدماتی':
      return l10n.service;
    case 'سایر':
      return l10n.other;
    default:
      return field;
  }
}

bool businessBlocksAccess(bool isDeleted, bool isDeletionPending) =>
    isDeleted || isDeletionPending;
