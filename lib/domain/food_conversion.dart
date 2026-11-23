import '../ai/ai_units.dart';
import 'food_matcher.dart';
import 'shopping_demand.dart';

/// Pretvaranje količine u osnovnu jedinicu namirnice (D1-010, predlog u
/// specs/018-ingredient-catalog/unit-conversion-proposal.md). Čista funkcija:
/// bez baze i mreže, isti ulaz daje isti rezultat.

/// Zašto količina ne može da se pretvori i ostaje za "Proveri količinu".
enum ConversionReview {
  /// Nema količine ili nije pozitivan konačan broj.
  unknownQuantity,

  /// Jedinica nije u rečniku ili se ne pretvara (npr. prstohvat); kuhinjske
  /// mere takođe, dok izvor nije uključio.
  unsupportedUnit,

  /// Pretvaranje traži gustinu ili težinu komada koje namirnica nema.
  missingFactor,

  /// Postoji više jednako prioritetnih faktora za istu namirnicu.
  conflictingFactor,

  /// "Pakovanje" bez izričito izabranog i poznatog pakovanja.
  unverifiedPackage,

  /// Količina ili zbir ne staje u celobrojne milionite delove; ne ograničava
  /// se tiho nego ide na proveru.
  outOfRange,
}

/// Najveća količina u milionitim delovima (ispod granice 64-bitnog celog
/// broja, da zaokruživanje i sabiranje ostanu tačni).
const maxConvertedMicros = 9000000000000000000;

sealed class UnitConversion {
  const UnitConversion();
}

/// Količina u celobrojnim milionitim delovima osnovne jedinice.
/// [approximate] je istina kad je korišćen faktor namirnice ili kuhinjska mera
/// (prikaz sa "~").
final class Converted extends UnitConversion {
  Converted(
    this.micros,
    this.base, {
    required this.approximate,
    Iterable<FoodFactorEvidence> factorEvidence = const [],
  }) : factorEvidence = List.unmodifiable(factorEvidence);

  factory Converted.fromApprovedSnapshotJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Nepoznata verzija konverzije');
    }
    final micros = json['micros'];
    final baseName = json['base_unit'];
    final approximate = json['approximate'];
    final evidenceJson = json['factor_evidence'];
    final base = baseName is String
        ? FoodBaseUnit.values.asNameMap()[baseName]
        : null;
    if (micros is! int || micros < 0 || micros > maxConvertedMicros) {
      throw const FormatException('Neispravna količina konverzije');
    }
    if (base == null || approximate is! bool || evidenceJson is! List) {
      throw const FormatException('Neispravan snimak konverzije');
    }
    return Converted(
      micros,
      base,
      approximate: approximate,
      factorEvidence: [
        for (final row in evidenceJson)
          if (row is Map<String, Object?>)
            FoodFactorEvidence.fromJson(row)
          else
            throw const FormatException('Neispravan dokaz faktora'),
      ],
    );
  }

  final int micros;
  final FoodBaseUnit base;
  final bool approximate;

  /// Dokaz za faktore korišćene pri obračunu. Sačuvana konverzija zadržava
  /// ovu listu i svoj [micros] i kada katalog kasnije dobije novu reviziju.
  final List<FoodFactorEvidence> factorEvidence;

  /// Sadržaj za čuvanje uz odobrenu količinu. Izvorna količina/jedinica
  /// ostaju polja potrošačkog reda; ovaj snimak beleži obračun i njegove
  /// faktore da promena kataloga ne preračuna već odobrenu stavku.
  Map<String, Object?> toApprovedSnapshotJson() => {
    'version': 1,
    'micros': micros,
    'base_unit': base.name,
    'approximate': approximate,
    'factor_evidence': factorEvidence.map((e) => e.toJson()).toList(),
  };
}

/// Originalna količina i jedinica ostaju neizmenjene; ništa se ne računa kao
/// nula ni kao izmišljen ekvivalent.
final class NeedsReview extends UnitConversion {
  const NeedsReview(this.reason);

  final ConversionReview reason;
}

/// Neto sadržaj jednog pakovanja, npr. 400 g.
final class PackageAmount {
  const PackageAmount(this.quantity, this.unit, {this.evidence});

  final double quantity;
  final String unit;
  final FoodFactorEvidence? evidence;
}

/// Vrsta promenljivog dokaza za pretvaranje količine namirnice.
enum FoodConversionFactorKind { densityGPerMl, pieceWeightG, packageAmount }

/// Neizmenljivi zapis izvora i revizije faktora. Deljeni faktori moraju biti
/// pregledani; kućni faktor važi samo u domaćinstvu koje ga je napravilo.
final class FoodConversionFactorRecord {
  const FoodConversionFactorRecord({
    required this.id,
    required this.foodId,
    required this.kind,
    required this.value,
    required this.source,
    required this.revision,
    this.householdId,
    this.unit,
    this.packageId,
    this.preparationState,
    this.reviewed = false,
  });

  final String id;
  final String foodId;
  final FoodConversionFactorKind kind;
  final double value;
  final String source;
  final int revision;
  final String? householdId;
  final String? unit;
  final String? packageId;
  final String? preparationState;
  final bool reviewed;

  bool get isValid {
    if (id.trim().isEmpty || foodId.trim().isEmpty || source.trim().isEmpty) {
      return false;
    }
    if (householdId != null && householdId!.trim().isEmpty) return false;
    if (revision <= 0 || !value.isFinite || value <= 0) return false;
    if (householdId == null && !reviewed) return false;
    if (kind == FoodConversionFactorKind.packageAmount) {
      return packageId != null &&
          packageId!.trim().isNotEmpty &&
          unit != null &&
          _validNet(PackageAmount(value, unit!));
    }
    return unit == null && packageId == null;
  }

  FoodFactorEvidence get evidence => FoodFactorEvidence(
    id: id,
    foodId: foodId,
    kind: kind,
    value: value,
    source: source,
    revision: revision,
    householdId: householdId,
    unit: unit,
    packageId: packageId,
    preparationState: preparationState,
  );
}

/// Verzija faktora koja se može kopirati uz odobrenu konverziju.
final class FoodFactorEvidence {
  const FoodFactorEvidence({
    required this.id,
    required this.foodId,
    required this.kind,
    required this.value,
    required this.source,
    required this.revision,
    required this.householdId,
    required this.unit,
    required this.packageId,
    required this.preparationState,
  });

  final String id;
  final String foodId;
  final FoodConversionFactorKind kind;
  final double value;
  final String source;
  final int revision;
  final String? householdId;
  final String? unit;
  final String? packageId;
  final String? preparationState;

  Map<String, Object?> toJson() => {
    'id': id,
    'food_id': foodId,
    'kind': kind.name,
    'value': value,
    'source': source,
    'revision': revision,
    'household_id': householdId,
    'unit': unit,
    'package_id': packageId,
    'preparation_state': preparationState,
  };

  factory FoodFactorEvidence.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = kindName is String
        ? FoodConversionFactorKind.values.asNameMap()[kindName]
        : null;
    final value = json['value'];
    final revision = json['revision'];
    final id = json['id'];
    final foodId = json['food_id'];
    final source = json['source'];
    if (kind == null ||
        value is! num ||
        !value.isFinite ||
        value <= 0 ||
        revision is! int ||
        revision <= 0 ||
        id is! String ||
        id.isEmpty ||
        foodId is! String ||
        foodId.isEmpty ||
        source is! String ||
        source.isEmpty) {
      throw const FormatException('Neispravan dokaz faktora');
    }
    final householdId = json['household_id'];
    final unit = json['unit'];
    final packageId = json['package_id'];
    final preparationState = json['preparation_state'];
    if ((householdId != null && householdId is! String) ||
        (unit != null && unit is! String) ||
        (packageId != null && packageId is! String) ||
        (preparationState != null && preparationState is! String)) {
      throw const FormatException('Neispravan opseg faktora');
    }
    if (kind == FoodConversionFactorKind.packageAmount) {
      if (unit is! String ||
          packageId is! String ||
          packageId.isEmpty ||
          !_validNet(PackageAmount(value.toDouble(), unit))) {
        throw const FormatException('Neispravan faktor pakovanja');
      }
    } else if (unit != null || packageId != null) {
      throw const FormatException('Faktor ne sme imati jedinicu pakovanja');
    }
    return FoodFactorEvidence(
      id: id,
      foodId: foodId,
      kind: kind,
      value: value.toDouble(),
      source: source,
      revision: revision,
      householdId: householdId as String?,
      unit: unit as String?,
      packageId: packageId as String?,
      preparationState: preparationState as String?,
    );
  }
}

/// Razrešava faktore za jednu hranu i jedno domaćinstvo. Kućni faktor ima
/// prednost; bez njega se koristi samo jedan pregledani deljeni faktor.
/// Više faktora istog prioriteta ostavlja tu vrstu za proveru.
FoodConversionFactors resolveFoodConversionFactors({
  required String foodId,
  required String householdId,
  required Iterable<FoodConversionFactorRecord> records,
  String? preparationState,
}) {
  final candidates = records
      .where(
        (r) =>
            r.isValid &&
            r.foodId == foodId &&
            r.preparationState == preparationState,
      )
      .toList();
  final conflicts = <FoodConversionFactorKind>{};
  final packages = <String, PackageAmount>{};
  final conflictingPackages = <String>{};
  FoodFactorEvidence? densityEvidence;
  FoodFactorEvidence? pieceWeightEvidence;

  List<FoodConversionFactorRecord> applicable(
    FoodConversionFactorKind kind, {
    String? packageId,
  }) {
    final household = candidates
        .where(
          (r) =>
              r.kind == kind &&
              r.householdId == householdId &&
              (packageId == null || r.packageId == packageId),
        )
        .toList();
    if (household.isNotEmpty) return household;
    return candidates
        .where(
          (r) =>
              r.kind == kind &&
              r.householdId == null &&
              r.reviewed &&
              (packageId == null || r.packageId == packageId),
        )
        .toList();
  }

  FoodConversionFactorRecord? select(FoodConversionFactorKind kind) {
    final matches = applicable(kind);
    if (matches.length > 1) {
      conflicts.add(kind);
      return null;
    }
    return matches.isEmpty ? null : matches.first;
  }

  final density = select(FoodConversionFactorKind.densityGPerMl);
  final pieceWeight = select(FoodConversionFactorKind.pieceWeightG);
  for (final record in candidates.where(
    (r) => r.kind == FoodConversionFactorKind.packageAmount,
  )) {
    final packageId = record.packageId!;
    final matches = applicable(
      FoodConversionFactorKind.packageAmount,
      packageId: packageId,
    );
    if (matches.length > 1) {
      conflictingPackages.add(packageId);
      continue;
    }
    final selected = matches.isEmpty ? null : matches.first;
    if (selected == null) continue;
    packages[packageId] = PackageAmount(
      selected.value,
      selected.unit!,
      evidence: selected.evidence,
    );
  }
  densityEvidence = density?.evidence;
  pieceWeightEvidence = pieceWeight?.evidence;
  return FoodConversionFactors(
    densityGPerMl: density?.value,
    pieceWeightG: pieceWeight?.value,
    packages: packages,
    densityEvidence: densityEvidence,
    pieceWeightEvidence: pieceWeightEvidence,
    conflictingKinds: conflicts,
    conflictingPackages: conflictingPackages,
  );
}

/// Faktori jedne namirnice, već razrešeni (zajednički ili domaćinstva).
/// Faktor koji nije pozitivan i konačan važi kao da ga nema.
final class FoodConversionFactors {
  const FoodConversionFactors({
    this.densityGPerMl,
    this.pieceWeightG,
    this.packages = const {},
    this.densityEvidence,
    this.pieceWeightEvidence,
    this.conflictingKinds = const {},
    this.conflictingPackages = const {},
  });

  /// Grama po mililitru.
  final double? densityGPerMl;

  /// Grama po komadu.
  final double? pieceWeightG;

  /// Pakovanja po identifikatoru (izričit izbor, ne nagađanje).
  final Map<String, PackageAmount> packages;
  final FoodFactorEvidence? densityEvidence;
  final FoodFactorEvidence? pieceWeightEvidence;
  final Set<FoodConversionFactorKind> conflictingKinds;
  final Set<String> conflictingPackages;

  double? get _density => _valid(densityGPerMl);
  double? get _pieceWeight => _valid(pieceWeightG);

  static double? _valid(double? v) =>
      v != null && v.isFinite && v > 0 ? v : null;
}

enum _Kind { mass, volume, count }

/// Neto sadržaj pakovanja je pozitivan konačan broj mase, zapremine ili
/// komada; kuhinjska mera, prstohvat ili "pakovanje" to nisu.
bool _validNet(PackageAmount p) {
  if (!p.quantity.isFinite || p.quantity <= 0) return false;
  final group = normalizeUnit(p.unit).group;
  return group == 'mass' || group == 'volume' || group == 'count:kom';
}

/// Pretvara [quantity] u [unit] u osnovnu jedinicu [target].
///
/// Jedinice iste dimenzije se pretvaraju tačno; ostalo traži faktor namirnice
/// i daje približan rezultat. Zaokruživanje na celobrojne milionite delove je
/// jednom, na kraju. [packageId] mora da bude izričito izabrano pakovanje.
UnitConversion convertQuantity({
  required double? quantity,
  required String? unit,
  required FoodBaseUnit target,
  FoodConversionFactors factors = const FoodConversionFactors(),
  bool kitchenMeasures = false,
  String? packageId,
}) {
  if (quantity == null || !quantity.isFinite || quantity <= 0) {
    return const NeedsReview(ConversionReview.unknownQuantity);
  }
  if (canonicalUnit(unit) == 'pakovanje') {
    if (packageId != null && factors.conflictingPackages.contains(packageId)) {
      return const NeedsReview(ConversionReview.conflictingFactor);
    }
    final pack = packageId == null ? null : factors.packages[packageId];
    if (pack == null || !_validNet(pack)) {
      return const NeedsReview(ConversionReview.unverifiedPackage);
    }
    final inner = convertQuantity(
      quantity: quantity * pack.quantity,
      unit: pack.unit,
      target: target,
      factors: FoodConversionFactors(
        densityGPerMl: factors.densityGPerMl,
        pieceWeightG: factors.pieceWeightG,
        densityEvidence: factors.densityEvidence,
        pieceWeightEvidence: factors.pieceWeightEvidence,
      ),
      // Kuhinjske procene važe za izvornu količinu, ne za neto pakovanja.
    );
    // Neto sadržaj je procena proizvođača, pa je rezultat približan.
    return inner is Converted
        ? Converted(
            inner.micros,
            inner.base,
            approximate: true,
            factorEvidence: [
              ...[pack.evidence].whereType<FoodFactorEvidence>(),
              ...inner.factorEvidence,
            ],
          )
        : inner;
  }

  final normalized = normalizeUnit(unit, kitchenMeasures: kitchenMeasures);
  final kind = switch (normalized.group) {
    'mass' => _Kind.mass,
    'volume' => _Kind.volume,
    'count:kom' => _Kind.count,
    _ => null,
  };
  if (kind == null) {
    return const NeedsReview(ConversionReview.unsupportedUnit);
  }
  // Kuhinjska mera (čaša, kašika...) je približna i kad se ne koristi faktor.
  final kitchenUsed =
      kitchenMeasures && normalizeUnit(unit).group.startsWith('unit:');
  final amount = quantity * normalized.factor;
  final density = factors._density;
  final pieceWeight = factors._pieceWeight;

  double? value;
  var usedFactor = false;
  switch ((target, kind)) {
    case (FoodBaseUnit.gram, _Kind.mass) ||
        (FoodBaseUnit.milliliter, _Kind.volume) ||
        (FoodBaseUnit.piece, _Kind.count):
      value = amount;
    case (FoodBaseUnit.gram, _Kind.volume):
      if (density != null) value = amount * density;
      usedFactor = true;
    case (FoodBaseUnit.gram, _Kind.count):
      if (pieceWeight != null) value = amount * pieceWeight;
      usedFactor = true;
    case (FoodBaseUnit.milliliter, _Kind.mass):
      if (density != null) value = amount / density;
      usedFactor = true;
    case (FoodBaseUnit.milliliter, _Kind.count):
      if (density != null && pieceWeight != null) {
        value = amount * pieceWeight / density;
      }
      usedFactor = true;
    case (FoodBaseUnit.piece, _Kind.mass):
      if (pieceWeight != null) value = amount / pieceWeight;
      usedFactor = true;
    case (FoodBaseUnit.piece, _Kind.volume):
      if (density != null && pieceWeight != null) {
        value = amount * density / pieceWeight;
      }
      usedFactor = true;
  }
  if (value == null) {
    final required = _requiredFactors(target, kind);
    final conflict = required.any(factors.conflictingKinds.contains);
    return NeedsReview(
      conflict
          ? ConversionReview.conflictingFactor
          : ConversionReview.missingFactor,
    );
  }
  final scaled = value * microsPerUnit;
  if (!scaled.isFinite || scaled > maxConvertedMicros) {
    return const NeedsReview(ConversionReview.outOfRange);
  }
  return Converted(
    scaled.round(),
    target,
    approximate: usedFactor || kitchenUsed,
    factorEvidence: _requiredFactors(target, kind)
        .map((required) => _evidenceFor(required, factors))
        .whereType<FoodFactorEvidence>(),
  );
}

Set<FoodConversionFactorKind> _requiredFactors(
  FoodBaseUnit target,
  _Kind input,
) => switch ((target, input)) {
  (FoodBaseUnit.gram, _Kind.mass) ||
  (FoodBaseUnit.milliliter, _Kind.volume) ||
  (FoodBaseUnit.piece, _Kind.count) => {},
  (FoodBaseUnit.gram, _Kind.volume) || (FoodBaseUnit.milliliter, _Kind.mass) =>
    {FoodConversionFactorKind.densityGPerMl},
  (FoodBaseUnit.gram, _Kind.count) ||
  (FoodBaseUnit.piece, _Kind.mass) => {FoodConversionFactorKind.pieceWeightG},
  (FoodBaseUnit.milliliter, _Kind.count) ||
  (FoodBaseUnit.piece, _Kind.volume) => {
    FoodConversionFactorKind.densityGPerMl,
    FoodConversionFactorKind.pieceWeightG,
  },
};

FoodFactorEvidence? _evidenceFor(
  FoodConversionFactorKind kind,
  FoodConversionFactors factors,
) => switch (kind) {
  FoodConversionFactorKind.densityGPerMl => factors.densityEvidence,
  FoodConversionFactorKind.pieceWeightG => factors.pieceWeightEvidence,
  FoodConversionFactorKind.packageAmount => null,
};

/// Zbir pretvorenih količina iste namirnice u istoj osnovnoj jedinici. Ono što
/// ne može da se pretvori ne ulazi u zbir nego u [review].
final class ConversionTotal {
  const ConversionTotal(this.micros, this.base, this.approximate, this.review);

  final int micros;
  final FoodBaseUnit? base;
  final bool approximate;
  final List<NeedsReview> review;
}

ConversionTotal totalOf(Iterable<UnitConversion> parts) {
  var micros = 0;
  var approximate = false;
  FoodBaseUnit? base;
  final review = <NeedsReview>[];
  for (final part in parts) {
    switch (part) {
      case Converted():
        if (base != null && base != part.base) {
          throw ArgumentError('Zbir traži istu osnovnu jedinicu');
        }
        if (part.micros > maxConvertedMicros - micros) {
          review.add(const NeedsReview(ConversionReview.outOfRange));
          continue;
        }
        base = part.base;
        micros += part.micros;
        approximate = approximate || part.approximate;
      case NeedsReview():
        review.add(part);
    }
  }
  return ConversionTotal(micros, base, approximate, review);
}
