import 'package:flutter/material.dart';

import '../../theme/tokens/color_schemes.dart';
import '../../theme/tokens/extensions.dart';

/// صفحهٔ مرجع تم — همهٔ توکن‌ها و اجزای M3 در یک جا.
///
/// این صفحه ابزار کار است، نه بخشی از محصول. قبل و بعد از هر تغییر در
/// `lib/theme/` آن را در light/dark و fa/en باز کنید. رگرسیون بصری را
/// این‌جا می‌بینید، نه در گزارش کاربر.
///
/// مسیر پیشنهادی: `/dev/theme` — فقط در debug ثبت شود.
class ThemeShowcasePage extends StatelessWidget {
  const ThemeShowcasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مرجع تم — Material 3'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'رنگ'),
              Tab(text: 'تایپ'),
              Tab(text: 'شکل و ارتفاع'),
              Tab(text: 'دکمه'),
              Tab(text: 'اجزا'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ColorTab(),
            _TypeTab(),
            _ShapeTab(),
            _ButtonTab(),
            _ComponentTab(),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 24, bottom: 8),
          child: Text(title, style: context.texts.titleMedium),
        ),
        ...children,
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Swatch extends StatelessWidget {
  final String label;
  final Color color;
  final Color onColor;
  const _Swatch(this.label, this.color, this.onColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 64,
      padding: const EdgeInsetsDirectional.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: context.shape.smallBorder,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(color: onColor),
      ),
    );
  }
}

class _ColorTab extends StatelessWidget {
  const _ColorTab();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.semantic;

    Widget role(String name, SemanticRole r) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Swatch(name, r.color, r.onColor),
            _Swatch('$name container', r.container, r.onContainer),
          ],
        );

    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _Section('نقش‌های اصلی', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Swatch('primary', c.primary, c.onPrimary),
            _Swatch('primaryContainer', c.primaryContainer, c.onPrimaryContainer),
            _Swatch('secondary', c.secondary, c.onSecondary),
            _Swatch(
                'secondaryContainer', c.secondaryContainer, c.onSecondaryContainer),
            _Swatch('tertiary', c.tertiary, c.onTertiary),
            _Swatch('tertiaryContainer', c.tertiaryContainer, c.onTertiaryContainer),
            _Swatch('error', c.error, c.onError),
            _Swatch('errorContainer', c.errorContainer, c.onErrorContainer),
          ]),
        ]),
        _Section('لایه‌های سطح — جایگزین سایه در M3', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Swatch('surfaceContainerLowest', c.surfaceContainerLowest, c.onSurface),
            _Swatch('surfaceContainerLow', c.surfaceContainerLow, c.onSurface),
            _Swatch('surfaceContainer', c.surfaceContainer, c.onSurface),
            _Swatch('surfaceContainerHigh', c.surfaceContainerHigh, c.onSurface),
            _Swatch('surfaceContainerHighest', c.surfaceContainerHighest, c.onSurface),
            _Swatch('inverseSurface', c.inverseSurface, c.onInverseSurface),
          ]),
        ]),
        _Section('رنگ‌های معنایی — افزودهٔ ما، نه بخشی از M3', [
          role('success', s.success),
          const SizedBox(height: 8),
          role('warning', s.warning),
          const SizedBox(height: 8),
          role('info', s.info),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Swatch('debit / بدهکار', s.debit, c.onError),
            _Swatch('credit / بستانکار', s.credit, c.surface),
            _Swatch('tableStripe', s.tableStripe, c.onSurface),
            _Swatch('tableSelection', s.tableSelection, c.onSecondaryContainer),
          ]),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _TypeTab extends StatelessWidget {
  const _TypeTab();

  @override
  Widget build(BuildContext context) {
    final t = context.texts;
    const sample = 'گردش حساب ۱۴۰۴ — Balance 1,250,000';

    Widget row(String name, TextStyle? style) => Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name · ${style?.fontSize?.toStringAsFixed(0)}px'
                ' · h${style?.height?.toStringAsFixed(2)}',
                style: t.labelSmall?.copyWith(color: context.colors.outline),
              ),
              Text(sample, style: style),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        row('displayLarge', t.displayLarge),
        row('displayMedium', t.displayMedium),
        row('displaySmall', t.displaySmall),
        row('headlineLarge', t.headlineLarge),
        row('headlineMedium', t.headlineMedium),
        row('headlineSmall', t.headlineSmall),
        row('titleLarge', t.titleLarge),
        row('titleMedium', t.titleMedium),
        row('titleSmall', t.titleSmall),
        row('bodyLarge', t.bodyLarge),
        row('bodyMedium', t.bodyMedium),
        row('bodySmall', t.bodySmall),
        row('labelLarge', t.labelLarge),
        row('labelMedium', t.labelMedium),
        row('labelSmall', t.labelSmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ShapeTab extends StatelessWidget {
  const _ShapeTab();

  @override
  Widget build(BuildContext context) {
    final sh = context.shape;
    final c = context.colors;

    Widget box(String label, BorderRadius radius) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 64,
              decoration: BoxDecoration(
                color: c.secondaryContainer,
                borderRadius: radius,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: context.texts.labelSmall),
          ],
        );

    Widget elev(String label, double e) => Material(
          elevation: e,
          color: c.surfaceAtElevation(e),
          shadowColor: c.shadow,
          borderRadius: sh.mediumBorder,
          child: SizedBox(
            width: 120,
            height: 72,
            child: Center(
              child: Text(label, style: context.texts.labelMedium),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _Section('مقیاس شکل', [
          Wrap(spacing: 16, runSpacing: 16, children: [
            box('extraSmall 4', sh.extraSmallBorder),
            box('small 8', sh.smallBorder),
            box('medium 12', sh.mediumBorder),
            box('large 16', sh.largeBorder),
            box('extraLarge 28', sh.extraLargeBorder),
            box('full', sh.full),
          ]),
        ]),
        _Section('ارتفاع — رنگ لایه + سایه', [
          Wrap(spacing: 16, runSpacing: 16, children: [
            elev('level0', AppElevation.level0),
            elev('level1', AppElevation.level1),
            elev('level2', AppElevation.level2),
            elev('level3', AppElevation.level3),
            elev('level4', AppElevation.level4),
            elev('level5', AppElevation.level5),
          ]),
        ]),
        _Section('کلاس اندازهٔ پنجرهٔ فعلی', [
          Text(
            '${context.windowSize.name} · ستون‌ها: ${context.windowSize.columns}'
            ' · حاشیه: ${context.windowSize.margin}',
            style: context.texts.bodyLarge,
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ButtonTab extends StatelessWidget {
  const _ButtonTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _Section('سلسله‌مراتب — از پررنگ به کم‌رنگ', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton(onPressed: () {}, child: const Text('ثبت سند')),
            FilledButton.tonal(onPressed: () {}, child: const Text('پیش‌نویس')),
            OutlinedButton(onPressed: () {}, child: const Text('انصراف')),
            TextButton(onPressed: () {}, child: const Text('راهنما')),
            ElevatedButton(onPressed: () {}, child: const Text('روی نقشه')),
          ]),
        ]),
        _Section('با آیکون', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('فاکتور جدید'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download),
              label: const Text('خروجی'),
            ),
          ]),
        ]),
        _Section('غیرفعال', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            const FilledButton(onPressed: null, child: Text('غیرفعال')),
            const OutlinedButton(onPressed: null, child: Text('غیرفعال')),
            const TextButton(onPressed: null, child: Text('غیرفعال')),
          ]),
        ]),
        _Section('گروه بخش‌بندی‌شده', [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('روز')),
              ButtonSegment(value: 1, label: Text('ماه')),
              ButtonSegment(value: 2, label: Text('سال')),
            ],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
        ]),
        _Section('آیکون و شناور', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.edit)),
            IconButton.filled(onPressed: () {}, icon: const Icon(Icons.save)),
            IconButton.filledTonal(
                onPressed: () {}, icon: const Icon(Icons.share)),
            IconButton.outlined(onPressed: () {}, icon: const Icon(Icons.print)),
            FloatingActionButton.small(
                onPressed: () {}, child: const Icon(Icons.add)),
          ]),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ComponentTab extends StatefulWidget {
  const _ComponentTab();

  @override
  State<_ComponentTab> createState() => _ComponentTabState();
}

class _ComponentTabState extends State<_ComponentTab> {
  bool _switchOn = true;
  bool _checked = true;
  int _radio = 1;
  double _slider = 0.4;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;

    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        _Section('کارت — سه واریانت M3', [
          Row(children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(16),
                  child: Text('filled', style: context.texts.bodyMedium),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card.outlined(
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(16),
                  child: Text('outlined', style: context.texts.bodyMedium),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: AppElevation.level1,
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(16),
                  child: Text('elevated', style: context.texts.bodyMedium),
                ),
              ),
            ),
          ]),
        ]),
        _Section('چیپ — نوع درست برای کار درست', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(label: const Text('assist'), onPressed: () {}),
            FilterChip(
              label: const Text('filter'),
              selected: true,
              onSelected: (_) {},
            ),
            InputChip(label: const Text('input'), onDeleted: () {}),
            const Chip(label: Text('suggestion')),
          ]),
        ]),
        _Section('وضعیت با رنگ معنایی', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _StatusPill('تأیید شده', s.success),
            _StatusPill('در انتظار', s.warning),
            _StatusPill('اطلاع', s.info),
          ]),
        ]),
        _Section('ورودی', [
          const TextField(
            decoration: InputDecoration(
              labelText: 'شمارهٔ سند',
              hintText: 'مثلاً ۱۴۰۴-۰۰۱۲',
            ),
          ),
          const SizedBox(height: 12),
          const TextField(
            decoration: InputDecoration(
              labelText: 'مبلغ',
              errorText: 'مبلغ نمی‌تواند صفر باشد',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
        ]),
        _Section('کنترل انتخاب', [
          Row(children: [
            Switch(
              value: _switchOn,
              onChanged: (v) => setState(() => _switchOn = v),
            ),
            Checkbox(
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
            ),
            Radio<int>(
              value: 1,
              groupValue: _radio,
              onChanged: (v) => setState(() => _radio = v ?? 1),
            ),
            Radio<int>(
              value: 2,
              groupValue: _radio,
              onChanged: (v) => setState(() => _radio = v ?? 2),
            ),
          ]),
          Slider(
            value: _slider,
            onChanged: (v) => setState(() => _slider = v),
          ),
        ]),
        _Section('پیشرفت', [
          const LinearProgressIndicator(value: 0.6),
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ]),
        _Section('نشان و اعلان', [
          Wrap(spacing: 24, children: [
            const Badge.count(
              count: 12,
              child: Icon(Icons.notifications_outlined),
            ),
            FilledButton.tonal(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('سند با موفقیت ثبت شد'),
                  action: SnackBarAction(label: 'بازگردانی', onPressed: () {}),
                ),
              ),
              child: const Text('نمایش SnackBar'),
            ),
          ]),
        ]),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final SemanticRole role;
  const _StatusPill(this.label, this.role);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: role.container,
        borderRadius: context.shape.full,
      ),
      child: Text(
        label,
        style: context.texts.labelLarge?.copyWith(color: role.onContainer),
      ),
    );
  }
}
