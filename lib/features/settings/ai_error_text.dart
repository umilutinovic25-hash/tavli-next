import '../../ai/ai_errors.dart';
import '../../ai/recipe_ai.dart';
import '../../domain/allergy.dart';

/// Poruka za korisnika umesto tehničke greške.
String aiErrorText(Object error) => switch (error) {
  AuthError() => 'Ključ nije ispravan ili je opozvan.',
  RateLimitError() => 'Limit je trenutno potrošen. Pokušaj malo kasnije.',
  TransientError() => 'Nema veze sa serverom. Proveri internet.',
  ModelNotFoundError() => 'Model nije dostupan za ovaj ključ.',
  InvalidOutputError() => 'AI je vratio neispravan odgovor.',
  BadRequestError(:final message) => 'Zahtev odbijen: $message',
  AllModelsExhausted(:final nextAvailableAt) =>
    nextAvailableAt == null
        ? 'Nijedan model nije dostupan. Proveri ključeve.'
        : 'Svi besplatni limiti su potrošeni. Pokušaj ponovo posle '
              '${_hhmm(nextAvailableAt.toLocal())}.',
  NotARecipeException() => 'Na slici nije pronađen recept.',
  AllergenViolation() => error.toString(),
  _ => 'Nešto nije u redu: $error',
};

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
