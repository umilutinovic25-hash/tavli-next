import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../shopping/shopping_providers.dart';

/// Čita istu ostavu u koju Nabavka prima kupljene namirnice.
final pantryItemsProvider = StreamProvider.autoDispose<List<PantryItemRow>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchItems(),
);
