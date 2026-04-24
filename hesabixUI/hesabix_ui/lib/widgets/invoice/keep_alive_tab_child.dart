import 'package:flutter/material.dart';

/// نگه‌داشتن state فرزند هنگام استفاده داخل [TabBarView] (جلوگیری از dispose شدن تب غیرفعال).
class KeepAliveTabChild extends StatefulWidget {
  const KeepAliveTabChild({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveTabChild> createState() => _KeepAliveTabChildState();
}

class _KeepAliveTabChildState extends State<KeepAliveTabChild>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
