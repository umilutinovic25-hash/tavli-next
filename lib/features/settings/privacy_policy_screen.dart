import 'package:flutter/material.dart';

/// Politika privatnosti (NACRT). Tekst mora da pregleda pravnik pre objave.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Politika privatnosti')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nacrt — pravni pregled je potreban pre objave',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final section in _sections) ...[
            const SizedBox(height: 20),
            Text(section.title, style: text.titleMedium),
            const SizedBox(height: 8),
            for (final p in section.paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(p, style: text.bodyMedium),
              ),
            for (final b in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Text('•  $b', style: text.bodyMedium),
              ),
          ],
        ],
      ),
    );
  }
}

class _Section {
  const _Section(
    this.title, {
    this.paragraphs = const [],
    this.bullets = const [],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

const _sections = [
  _Section(
    'Ko smo i na šta se ovo odnosi',
    paragraphs: [
      'Tavli je aplikacija za recepte, planove obroka, liste za kupovinu i '
          'ostavu. Ova politika opisuje koje podatke obrađujemo kada koristite '
          'aplikaciju.',
    ],
  ),
  _Section(
    'Koje podatke prikupljamo',
    paragraphs: [
      'Podatke unosite sami ili ih aplikacija beleži dok je koristite:',
    ],
    bullets: [
      'nalog: email adresa i ime,',
      'recepti: naslov, sastojci, koraci, porcije, izvor (unos, veb-stranica, '
          'fotografija ili naziv jela) i veze između sastojaka i koraka,',
      'planovi obroka i obroci u planu,',
      'liste za kupovinu i stavke na njima,',
      'ostava (zalihe),',
      'sačuvane pretrage recepata,',
      'pravila po danima i vreme za kuvanje po danima,',
      'alergije (zdravstveni podatak). Alergije koje upišete vide ostali '
          'članovi domaćinstva, da bi aplikacija mogla da proveri recepte za '
          'sve,',
      'fotografije jela i recepata koje pošaljete.',
    ],
  ),
  _Section(
    'Gde se podaci čuvaju',
    paragraphs: [
      'Podaci naloga i sadržaj aplikacije čuvaju se na Supabase serveru u EU '
          'regionu. Svaki red je vezan za vaš nalog i dostupan samo njemu.',
      'Na uređaju se čuva lokalna kopija podataka, da aplikacija radi i bez '
          'mreže. AI ključevi i sesija prijave čuvaju se u sigurnom skladištu '
          'uređaja (Keychain, odnosno Keystore) i ne šalju se na naš server.',
    ],
  ),
  _Section(
    'AI servisi',
    paragraphs: [
      'Kada zatražite pomoć veštačke inteligencije (recept iz fotografije, '
          'recept iz naziva jela, izmena recepta u razgovoru), šalju se '
          'fotografija jela i/ili tekst recepta sledećim servisima:',
    ],
    bullets: ['Google Gemini,', 'Groq,', 'OpenRouter.'],
  ),
  _Section(
    'Koliko čuvamo podatke',
    paragraphs: [
      'Podatke čuvamo dok ih ne obrišete ili dok ne obrišete nalog. Brisanje '
          'pojedinačne stavke uklanja je iz aplikacije i sa servera.',
      'Odjava ne briše podatke. Brisanje naloga (Profil → Obriši nalog) briše '
          'nalog i podatke povezane sa njim, na serveru i na uređaju. '
          '[pravni pregled: šta se dešava sa podacima domaćinstva kad nalog '
          'obriše vlasnik]',
    ],
  ),
  _Section(
    'Vaša prava',
    bullets: [
      'Pristup: sve podatke vidite u aplikaciji.',
      'Izvoz: Profil → Izvezi moje podatke pravi JSON fajl sa vašim podacima. '
          'Obuhvata podatke aktivnog domaćinstva i vaše članstvo u njemu, bez '
          'podataka drugih članova. Izvoz ne sadrži AI ključeve, tokene sesije '
          'ni podatke iz sigurnog skladišta.',
      'Ispravka: podatke menjate direktno u aplikaciji.',
      'Brisanje: pojedinačne stavke ili ceo nalog (Profil → Obriši nalog).',
      '[pravni pregled: dodatna prava prema GDPR-u i zakonu Republike Srbije]',
    ],
  ),
  _Section(
    'Kontakt',
    paragraphs: [
      'Za pitanja o privatnosti i zahteve za pristup ili brisanje podataka '
          'pišite na: [email za privatnost]',
    ],
  ),
];
