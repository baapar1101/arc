import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/business_models.dart';

String localizedBusinessType(AppLocalizations t, BusinessType type) {
  switch (type) {
    case BusinessType.company:
      return t.company;
    case BusinessType.shop:
      return t.shop;
    case BusinessType.store:
      return t.store;
    case BusinessType.union:
      return t.union;
    case BusinessType.club:
      return t.club;
    case BusinessType.institute:
      return t.institute;
    case BusinessType.individual:
      return t.individual;
  }
}

String localizedBusinessField(AppLocalizations t, BusinessField field) {
  switch (field) {
    case BusinessField.manufacturing:
      return t.manufacturing;
    case BusinessField.commercial:
      return t.trading;
    case BusinessField.service:
      return t.service;
    case BusinessField.other:
      return t.other;
  }
}

IconData businessTypeIcon(BusinessType type) {
  switch (type) {
    case BusinessType.company:
      return Icons.apartment_rounded;
    case BusinessType.shop:
      return Icons.storefront_rounded;
    case BusinessType.store:
      return Icons.store_mall_directory_rounded;
    case BusinessType.union:
      return Icons.groups_rounded;
    case BusinessType.club:
      return Icons.sports_rounded;
    case BusinessType.institute:
      return Icons.school_rounded;
    case BusinessType.individual:
      return Icons.person_rounded;
  }
}

IconData businessFieldIcon(BusinessField field) {
  switch (field) {
    case BusinessField.manufacturing:
      return Icons.precision_manufacturing_rounded;
    case BusinessField.commercial:
      return Icons.local_shipping_rounded;
    case BusinessField.service:
      return Icons.handshake_rounded;
    case BusinessField.other:
      return Icons.category_rounded;
  }
}
