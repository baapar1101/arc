import 'package:flutter/material.dart';

/// بدنهٔ پنل با چند تب: تب فعال همیشه ویجت زندهٔ [GoRouter] است؛ تب‌های غیرفعال
/// آخرین ویجت قبل از ترک را نگه می‌دارند تا اسکرول و فرم تا بازگشت حفظ شود.
///
/// [RestorationScope] به هر اسلات کمک می‌کند در صورت فعال بودن بازیابی سیستم،
/// وضعیت UI بهتر حفظ شود. تب‌های غیرفعال از فوکوس و ناوبری معنایی کنار گذاشته می‌شوند.
///
/// نکته: با بازگشت دوباره به همان تب، روتر معمولاً صفحه را دوباره می‌سازد؛ با
/// [hesabixNoTransitionPage] در `main.dart` کلید صفحه به مسیر پایدار گره خورده تا
/// در صورت امکان بازیافت Element بهتر شود.
class BusinessShellTabbedBody extends StatefulWidget {
  const BusinessShellTabbedBody({
    super.key,
    required this.paths,
    required this.activePath,
    required this.routerChild,
  });

  final List<String> paths;
  final String activePath;
  final Widget routerChild;

  @override
  State<BusinessShellTabbedBody> createState() => _BusinessShellTabbedBodyState();
}

class _BusinessShellTabbedBodyState extends State<BusinessShellTabbedBody> {
  final Map<String, Widget> _frozen = {};
  String? _lastActive;
  Widget? _lastLive;

  String _restorationIdForPath(String path) => 'business_shell_tab_${path.hashCode}';

  @override
  Widget build(BuildContext context) {
    final paths = widget.paths;
    final ap = widget.activePath;
    final live = widget.routerChild;

    _frozen.removeWhere((path, _) => !paths.contains(path));

    if (_lastActive != null && _lastActive != ap && _lastLive != null) {
      _frozen[_lastActive!] = _lastLive!;
    }

    if (paths.isEmpty || !paths.contains(ap)) {
      _lastActive = ap;
      _lastLive = live;
      return live;
    }

    final idx = paths.indexOf(ap);
    final safeIdx = idx < 0 ? 0 : idx;

    final children = <Widget>[
      for (final p in paths)
        KeyedSubtree(
          key: PageStorageKey<String>('business_shell_tab_$p'),
          child: RestorationScope(
            restorationId: _restorationIdForPath(p),
            child: p == ap
                ? live
                : ExcludeSemantics(
                    excluding: true,
                    child: ExcludeFocus(
                      excluding: true,
                      child: TickerMode(
                        enabled: false,
                        child: _frozen[p] ?? const SizedBox.expand(),
                      ),
                    ),
                  ),
          ),
        ),
    ];

    _lastActive = ap;
    _lastLive = live;

    return IndexedStack(
      index: safeIdx.clamp(0, children.length - 1),
      sizing: StackFit.expand,
      children: children,
    );
  }
}
