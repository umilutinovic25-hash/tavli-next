-- 027: veze sastojaka i koraka. Koraci ostaju lista teksta (`steps`), pa
-- ih starije verzije aplikacije čitaju i pišu kao ranije; veze su u
-- posebnoj koloni, a svaka pamti tekst koraka i id sastojka. Upis koji ne
-- šalje `step_links` (stariji klijent) ostavlja veze netaknute.
alter table public.recipes
  add column step_links jsonb check (step_links is null or jsonb_typeof(step_links) = 'array');
