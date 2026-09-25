/// مراحل راه‌اندازی اولیهٔ اپ — مبنای پیشرفت determinate در splash.
enum AppInitPhase {
  language(1, 'loadingLanguageSettings'),
  calendar(2, 'loadingCalendarSettings'),
  theme(3, 'loadingThemeSettings'),
  auth(4, 'loadingAuthentication'),
  finalizing(5, 'initializing');

  const AppInitPhase(this.step, this.statusKey);

  final int step;
  final String statusKey;

  static const int totalSteps = 5;

  /// پیشرفت پایان این مرحله در بازهٔ ۰ تا ۱ (فقط init داخل Flutter).
  double get endProgress => step / totalSteps;

  /// پیشرفت ابتدای این مرحله.
  double get startProgress => (step - 1) / totalSteps;

  /// شمارهٔ مرحله در تجربهٔ وب (۳ مرحلهٔ دانلود + ۵ مرحلهٔ init).
  int get webStep => webDownloadSteps + step;

  static const int webDownloadSteps = 3;
  static const int webTotalSteps = webDownloadSteps + totalSteps;

  /// نگاشت پیشرفت init (۰–۱) به درصد کلی وب پس از دانلود (۹۶–۱۰۰).
  static double webPercentFromInitProgress(double initProgress) {
    const start = 96.0;
    const span = 4.0;
    return start + initProgress.clamp(0.0, 1.0) * span;
  }
}

class AppInitProgress {
  final AppInitPhase phase;
  final double progress;

  const AppInitProgress({
    required this.phase,
    required this.progress,
  });

  const AppInitProgress.initial()
      : phase = AppInitPhase.language,
        progress = 0;

  int get currentStep => phase.step;
  int get totalSteps => AppInitPhase.totalSteps;

  int get webCurrentStep => phase.webStep;
  int get webTotalSteps => AppInitPhase.webTotalSteps;

  double get webPercent => AppInitPhase.webPercentFromInitProgress(progress);

  String get statusKey => phase.statusKey;

  AppInitProgress copyWith({
    AppInitPhase? phase,
    double? progress,
  }) {
    return AppInitProgress(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
    );
  }
}
