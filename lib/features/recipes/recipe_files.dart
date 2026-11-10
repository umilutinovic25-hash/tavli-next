import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart'
    show ShareParams, SharePlus, ShareResultStatus;

/// Bira JSON fajl recepta i čuva ili deli izvezen recept.
abstract class RecipeFiles {
  /// Tekst izabranog fajla ili null ako je korisnik odustao.
  Future<String?> pickJson();

  /// Na Mac-u bira mesto za čuvanje, na telefonu otvara sistemsko deljenje.
  /// Vraća false kad je korisnik odustao.
  Future<bool> saveJson(String fileName, String content, {Rect? origin});
}

const _jsonTypes = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  mimeTypes: ['application/json', 'application/ld+json'],
  uniformTypeIdentifiers: ['public.json'],
);

class SystemRecipeFiles implements RecipeFiles {
  @override
  Future<String?> pickJson() async {
    final file = await openFile(acceptedTypeGroups: [_jsonTypes]);
    return file?.readAsString();
  }

  @override
  Future<bool> saveJson(String fileName, String content, {Rect? origin}) async {
    final file = XFile.fromData(
      utf8.encode(content),
      mimeType: 'application/json',
      name: fileName,
    );
    if (Platform.isMacOS) {
      final location = await getSaveLocation(
        acceptedTypeGroups: [_jsonTypes],
        suggestedName: fileName,
      );
      if (location == null) return false;
      await file.saveTo(location.path);
      return true;
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        sharePositionOrigin: origin,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}

/// "Pita sa jabukama" → "Pita-sa-jabukama.json".
String recipeFileName(String title) {
  final slug = title
      .trim()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? 'recept' : slug}.json';
}
