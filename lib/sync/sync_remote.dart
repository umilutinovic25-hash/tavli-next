import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

/// Greška pri slanju ili preuzimanju. [code] je kod greške (HTTP status ili
/// Postgres kod), nikad sadržaj zapisa.
sealed class SyncError implements Exception {
  const SyncError(this.code);

  final String code;

  @override
  String toString() => '$runtimeType($code)';
}

/// Preuzimanje je prekinuto jer su se pozicije u međuvremenu obrisale
/// (promena članstva); novo preuzimanje kreće od početka.
class CancelledSyncError extends SyncError {
  const CancelledSyncError() : super('cancelled');
}

/// Nema mreže, istek vremena, 5xx ili 429: pokušava se ponovo kasnije.
class TransientSyncError extends SyncError {
  const TransientSyncError(super.code);
}

/// 401: sesiju treba obnoviti.
class UnauthorizedSyncError extends SyncError {
  const UnauthorizedSyncError() : super('401');
}

/// Server trajno odbija zapis (neispravni podaci, prava): ne pokušava se
/// ponovo, ali ne blokira ostale izmene.
class PermanentSyncError extends SyncError {
  const PermanentSyncError(super.code);
}

/// Tabele na serveru (PostgREST). Baca [SyncError].
abstract interface class SyncRemote {
  /// Upsert po id-ju ([onConflict]).
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    String onConflict = 'id',
  });

  Future<void> delete(String table, List<String> ids, {String idColumn = 'id'});

  Future<void> updateProfileName(String userId, String name);

  /// Redovi posle (since, afterId), redom po ([timeColumn], [idColumn]).
  Future<List<Map<String, Object?>>> fetchSince(
    String table, {
    required int limit,
    String? since,
    String? afterId,
    String timeColumn = 'updated_at',
    String idColumn = 'id',
  });
}

/// Privatni bucket sa slikama. Baca [SyncError].
abstract interface class PhotoRemote {
  /// Upsert: ponovljeno slanje je bezopasno.
  Future<void> upload(String objectKey, Uint8List jpeg);

  Future<Uint8List> download(String objectKey);

  Future<void> remove(List<String> objectKeys);
}

/// Kod Postgres/PostgREST/HTTP greške → vrsta greške (research R7).
SyncError classifySyncError(String code) {
  if (code == '401' || code.startsWith('PGRST3')) {
    return const UnauthorizedSyncError();
  }
  final status = code.length == 3 ? int.tryParse(code) : null;
  if (status != null) {
    return status == 408 || status == 429 || status >= 500
        ? TransientSyncError(code)
        : PermanentSyncError(code);
  }
  // Postgres klase: veza, resursi, operator, sistem, konflikt transakcije.
  const transientClasses = {'08', '40', '53', '54', '57', '58', 'XX'};
  if (code.length == 5 && transientClasses.contains(code.substring(0, 2))) {
    return TransientSyncError(code);
  }
  return PermanentSyncError(code);
}

Future<T> _guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on PostgrestException catch (e) {
    throw classifySyncError(e.code ?? '500');
  } on StorageException catch (e) {
    final message = e.message.toLowerCase();
    if (message.contains('jwt') || message.contains('"exp"')) {
      throw const UnauthorizedSyncError();
    }
    throw classifySyncError(e.statusCode ?? '500');
  } on SocketException {
    throw const TransientSyncError('offline');
  } on TimeoutException {
    throw const TransientSyncError('timeout');
  } on http.ClientException {
    throw const TransientSyncError('offline');
  }
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  PostgrestQueryBuilder<void> _from(String table) => _client.rest.from(table);

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    String onConflict = 'id',
  }) => _guard(() async {
    await _from(table).upsert(rows, onConflict: onConflict);
  });

  @override
  Future<void> delete(
    String table,
    List<String> ids, {
    String idColumn = 'id',
  }) => _guard(() async {
    await _from(table).delete().inFilter(idColumn, ids);
  });

  @override
  Future<void> updateProfileName(String userId, String name) =>
      _guard(() async {
        await _from('profiles').update({'display_name': name}).eq('id', userId);
      });

  @override
  Future<List<Map<String, Object?>>> fetchSince(
    String table, {
    required int limit,
    String? since,
    String? afterId,
    String timeColumn = 'updated_at',
    String idColumn = 'id',
  }) => _guard(() async {
    var q = _from(table).select();
    if (since != null) {
      q = afterId == null
          ? q.gte(timeColumn, since)
          : q.or(
              '$timeColumn.gt."$since",'
              'and($timeColumn.eq."$since",$idColumn.gt."$afterId")',
            );
    }
    final rows = await q
        .order(timeColumn, ascending: true)
        .order(idColumn, ascending: true)
        .limit(limit);
    return [for (final r in rows) Map<String, Object?>.of(r)];
  });
}

class SupabasePhotoRemote implements PhotoRemote {
  SupabasePhotoRemote(this._client);

  final SupabaseClient _client;

  static const bucket = 'recipe-photos';

  StorageFileApi get _bucket => _client.storage.from(bucket);

  @override
  Future<void> upload(String objectKey, Uint8List jpeg) => _guard(() async {
    await _bucket.uploadBinary(
      objectKey,
      jpeg,
      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
    );
  });

  @override
  Future<Uint8List> download(String objectKey) =>
      _guard(() => _bucket.download(objectKey));

  @override
  Future<void> remove(List<String> objectKeys) => _guard(() async {
    await _bucket.remove(objectKeys);
  });
}
