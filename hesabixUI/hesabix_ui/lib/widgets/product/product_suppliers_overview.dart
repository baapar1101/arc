import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/person_social_platforms.dart';
import '../../utils/product_supplier_display.dart';
import '../../utils/responsive_helper.dart';

/// کارت تأمین‌کنندگان در تب «اطلاعات کلی» جزئیات کالا.
class ProductSuppliersOverview extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool hydrating;
  final bool showTitle;

  const ProductSuppliersOverview({
    super.key,
    required this.product,
    this.hydrating = false,
    this.showTitle = true,
  });

  bool _isFa(BuildContext context) =>
      Localizations.localeOf(context).languageCode != 'en';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fa = _isFa(context);
    final suppliers = productSuppliersOf(product);
    final compact = ResponsiveHelper.isMobile(context);
    final title = fa ? 'تأمین‌کنندگان کالا' : 'Product suppliers';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (hydrating && suppliers.isEmpty)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        if (showTitle) SizedBox(height: compact ? 8 : 12),
        if (!showTitle && hydrating && suppliers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (suppliers.isEmpty)
          Text(
            hydrating
                ? (fa ? 'در حال بارگذاری تأمین‌کنندگان…' : 'Loading suppliers…')
                : (fa
                    ? 'برای این کالا تأمین‌کننده‌ای ثبت نشده است.'
                    : 'No supplier is linked to this product.'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...suppliers.map((row) => _SupplierOverviewCard(row: row, compact: compact, isFa: fa)),
      ],
    );
  }
}

class _SupplierOverviewCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool compact;
  final bool isFa;

  const _SupplierOverviewCard({
    required this.row,
    required this.compact,
    required this.isFa,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferred = row['is_preferred'] == true;
    final name = productSupplierRowName(row);
    final personName = row['person_name']?.toString().trim() ?? '';
    final showPerson = personName.isNotEmpty && personName != name;
    final phone = row['phone']?.toString().trim() ?? '';
    final email = row['email']?.toString().trim() ?? '';
    final website = row['website']?.toString().trim() ?? '';
    final notes = row['notes']?.toString().trim() ?? '';
    final social = (row['social_contacts'] is List)
        ? (row['social_contacts'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((s) => (s['value']?.toString().trim() ?? '').isNotEmpty)
            .toList()
        : const <Map<String, dynamic>>[];

    final scheme = theme.colorScheme;
    final bg = preferred ? scheme.primaryContainer.withValues(alpha: 0.45) : scheme.surfaceContainerHighest;
    final border = preferred ? scheme.primary.withValues(alpha: 0.35) : scheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                preferred ? Icons.star : Icons.storefront_outlined,
                size: 20,
                color: preferred ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isEmpty ? (isFa ? 'تأمین‌کننده' : 'Supplier') : name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (preferred)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isFa ? 'ترجیحی' : 'Preferred',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (showPerson) ...[
            const SizedBox(height: 4),
            Text(
              personName,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (phone.isNotEmpty || email.isNotEmpty || website.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (phone.isNotEmpty)
                  _ContactChip(
                    icon: Icons.phone_outlined,
                    label: phone,
                    onTap: () => _launch(Uri(scheme: 'tel', path: phone)),
                  ),
                if (email.isNotEmpty)
                  _ContactChip(
                    icon: Icons.email_outlined,
                    label: email,
                    onTap: () => _launch(Uri(scheme: 'mailto', path: email)),
                  ),
                if (website.isNotEmpty)
                  _ContactChip(
                    icon: Icons.language_outlined,
                    label: website,
                    onTap: () => _launch(_websiteUri(website)),
                  ),
              ],
            ),
          ],
          if (social.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: social.map((s) {
                final key = s['platform_key']?.toString() ?? '';
                final value = s['value']?.toString().trim() ?? '';
                final label = personSocialPlatformLabelFa(key, customLabel: s['custom_label']?.toString());
                return _ContactChip(
                  icon: Icons.chat_bubble_outline,
                  label: '$label: $value',
                );
              }).toList(),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              notes,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Uri _websiteUri(String raw) {
    final t = raw.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) {
      return Uri.parse(t);
    }
    return Uri.parse('https://$t');
  }

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ContactChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            label,
            style: theme.textTheme.labelMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

/// بارگذاری GET کامل کالا و ادغام با ردیف لیست، بدون ریست شدن تب‌ها در حد ممکن.
class ProductDetailsHydrator extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic> initialProduct;
  final Future<Map<String, dynamic>> Function(int productId) loadProduct;
  final Widget Function(BuildContext context, Map<String, dynamic> product, bool hydrating) builder;

  const ProductDetailsHydrator({
    super.key,
    required this.businessId,
    required this.initialProduct,
    required this.loadProduct,
    required this.builder,
  });

  @override
  State<ProductDetailsHydrator> createState() => _ProductDetailsHydratorState();
}

class _ProductDetailsHydratorState extends State<ProductDetailsHydrator> {
  late Map<String, dynamic> _product;
  bool _hydrating = true;

  @override
  void initState() {
    super.initState();
    _product = Map<String, dynamic>.from(widget.initialProduct);
    _hydrate();
  }

  Future<void> _hydrate() async {
    final rawId = _product['id'];
    final id = rawId is int
        ? rawId
        : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''));
    if (id == null) {
      if (mounted) setState(() => _hydrating = false);
      return;
    }
    try {
      final full = await widget.loadProduct(id);
      if (!mounted) return;
      setState(() {
        if (full.isNotEmpty && full['id'] != null) {
          _product = mergeProductDetailMaps(widget.initialProduct, full);
        }
        _hydrating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hydrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _product, _hydrating);
  }
}
