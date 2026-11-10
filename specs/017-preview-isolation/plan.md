# Plan
Grana iz origin/main. Mali adapter nad postojećim SecretStorage, izabran jednom
u provider-u koji dele SessionStore i SecureKeyStore. Default vraća originalno
skladište, eksplicitni lokalni preview dodaje prefiks svim fizičkim ključevima.
Prvo fake testovi, zatim adapter/wiring, pune provere i native lokalna prijava.
Bez šeme, novih zavisnosti, promene prava ili pristupa starim Keychain stavkama.
Zaštićeni SecurityAgent nije automatizovan; prethodni zahtev je korisnik odbio.
