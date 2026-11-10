import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/animations/motion.dart';
import '../../data/database.dart';
import '../../providers.dart';

/// Drži ekran upaljenim (sistem ga inače gasi posle par minuta).
abstract interface class ScreenWakeLock {
  Future<void> enable();
  Future<void> disable();
}

class WakelockPlusScreenWakeLock implements ScreenWakeLock {
  const WakelockPlusScreenWakeLock();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

final screenWakeLockProvider = Provider<ScreenWakeLock>(
  (ref) => const WakelockPlusScreenWakeLock(),
);

/// Platform calls must complete in order even when scopes are replaced quickly.
class _WakeLockQueue {
  _WakeLockQueue(this.lock);

  final ScreenWakeLock lock;
  Future<void> _pending = Future.value();
  int _holders = 0;

  void apply(bool on) {
    final wasHeld = _holders > 0;
    _holders += on ? 1 : -1;
    final held = _holders > 0;
    if (held == wasHeld) return;
    _pending = _pending.then((_) async {
      try {
        await (held ? lock.enable() : lock.disable());
      } on Exception catch (e) {
        if (kDebugMode) debugPrint('Ekran: zahtev nije uspeo ($e)');
      }
    });
  }
}

final _wakeLockQueueProvider = Provider<_WakeLockQueue>(
  (ref) => _WakeLockQueue(ref.watch(screenWakeLockProvider)),
);

/// "Ne gasi ekran" dok je recept otvoren; čuva se u AppSettings.
class KeepScreenOn extends AsyncNotifier<bool> {
  static const settingKey = 'keep_screen_on';

  @override
  Future<bool> build() async {
    final db = ref.watch(databaseProvider);
    final row = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(settingKey))).getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> set(bool on) async {
    state = AsyncData(on);
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: settingKey, value: '$on'),
          mode: InsertMode.insertOrReplace,
        );
  }
}

final keepScreenOnProvider = AsyncNotifierProvider<KeepScreenOn, bool>(
  KeepScreenOn.new,
);

/// Dok je ovaj widget na ekranu i opcija uključena, ekran se ne gasi.
class KeepScreenOnScope extends ConsumerStatefulWidget {
  const KeepScreenOnScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeepScreenOnScope> createState() => _KeepScreenOnScopeState();
}

class _KeepScreenOnScopeState extends ConsumerState<KeepScreenOnScope> {
  late final _WakeLockQueue _lock = ref.read(_wakeLockQueueProvider);
  bool _held = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      keepScreenOnProvider,
      (_, next) => _apply(next.value ?? false),
      fireImmediately: true,
    );
  }

  void _apply(bool on) {
    if (on == _held) return;
    _held = on;
    _lock.apply(on);
  }

  @override
  void dispose() {
    if (_held) _lock.apply(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dugme u traci recepta. Status se vidi u svakom trenutku: uključeno je
/// sunce na obojenoj podlozi („ekran ostaje budan“), isključeno je mesec
/// bez podloge („ekran sme da zaspi“). Promena se animira (sunce izlazi,
/// mesec zalazi), osim kad sistem traži smanjeno kretanje.
class KeepScreenOnButton extends ConsumerWidget {
  const KeepScreenOnButton({super.key});

  static const onIcon = Icons.light_mode;
  static const offIcon = Icons.bedtime_outlined;

  static String tooltipFor({required bool on}) =>
      on ? 'Ne gasi ekran: uključeno' : 'Ne gasi ekran: isključeno';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(keepScreenOnProvider).value ?? false;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltipFor(on: on),
      isSelected: on,
      style: IconButton.styleFrom(
        backgroundColor: on ? scheme.primaryContainer : Colors.transparent,
        foregroundColor: on
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant,
        animationDuration: TavliMotion.duration(
          context,
          TavliMotion.transition,
        ),
      ),
      icon: AnimatedSwitcher(
        duration: TavliMotion.duration(context, TavliMotion.reveal),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: -0.25, end: 0).animate(animation),
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: Icon(on ? onIcon : offIcon, key: ValueKey(on)),
      ),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        await ref.read(keepScreenOnProvider.notifier).set(!on);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                on
                    ? 'Ekran se gasi kao i obično.'
                    : 'Ekran se neće gasiti dok je recept otvoren.',
              ),
            ),
          );
      },
    );
  }
}
