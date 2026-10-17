import 'package:flutter/widgets.dart';
import 'package:sesli_kitap/src/theme/palette.dart';

class AppSettings extends ChangeNotifier {
  AppSettings({
    this.theme = AppTheme.cognac,
    this.mode = AppMode.dark,
    this.highContrast = false,
    this.dyslexia = false,
    this.fontScale = 1.0,
    this.sonic = true,
    this.daylight = true,
    this.onChanged,
  });

  AppTheme theme;
  AppMode mode;
  bool highContrast;
  bool dyslexia;
  double fontScale;
  bool sonic;
  bool daylight;

  final void Function()? onChanged;

  void setTheme(AppTheme v) {
    if (theme == v) return;
    theme = v;
    notifyListeners();
    onChanged?.call();
  }

  void setMode(AppMode v) {
    if (mode == v) return;
    mode = v;
    notifyListeners();
    onChanged?.call();
  }

  void toggleHighContrast() {
    highContrast = !highContrast;
    notifyListeners();
    onChanged?.call();
  }

  void toggleDyslexia() {
    dyslexia = !dyslexia;
    notifyListeners();
    onChanged?.call();
  }

  void setFontScale(double v) {
    if (fontScale == v) return;
    fontScale = v;
    notifyListeners();
    onChanged?.call();
  }

  void toggleSonic() {
    sonic = !sonic;
    notifyListeners();
    onChanged?.call();
  }

  void toggleDaylight() {
    daylight = !daylight;
    notifyListeners();
    onChanged?.call();
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    required AppSettings settings,
    required super.child,
    super.key,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(s != null, 'AppSettingsScope bulunamadi');
    return s!.notifier!;
  }
}
