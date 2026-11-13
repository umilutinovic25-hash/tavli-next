import '../domain/theme_choice.dart';
import 'database.dart';

/// Podešavanja aplikacije kao parovi ključ → vrednost u `AppSettings`.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const themeKey = 'theme';
  static const themeModeKey = 'theme_mode';
  static const univerexportPriceCategoryKey = 'univerexport_price_category';

  Future<String?> get(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  Future<ThemeChoice> loadTheme() async => ThemeChoice.fromSettings(
    theme: await get(themeKey),
    mode: await get(themeModeKey),
  );

  Future<void> saveTheme(ThemeChoice choice) => _db.transaction(() async {
    await set(themeKey, choice.theme.name);
    await set(themeModeKey, choice.mode.name);
  });
}
