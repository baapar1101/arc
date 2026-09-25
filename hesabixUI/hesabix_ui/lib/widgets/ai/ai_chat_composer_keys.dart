/// میانبر صفحه‌کلید composer جدا از ویجت (UX-09).
bool composerEnterShouldSend({
  required bool shiftPressed,
  required bool compactLayout,
}) {
  if (compactLayout) return false;
  return !shiftPressed;
}
