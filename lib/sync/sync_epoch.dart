/// Brojač koji se povećava kad se pozicije preuzimanja obrišu (promena
/// članstva). Preuzimanje koje je počelo pre toga ne sme da upiše svoju
/// staru poziciju ni redove domaćinstva koje je u međuvremenu obrisano.
class SyncEpoch {
  var _value = 0;

  int get value => _value;

  void bump() => _value++;
}
