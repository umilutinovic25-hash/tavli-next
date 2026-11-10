-- 026: obrok van kuće. Stavka plana dobija vrstu: `cook` (postojeći i
-- novi obroci koji se kuvaju) ili `away` (restoran, kod roditelja,
-- preskačem): mesto je zauzeto, a nabavka ga ne vidi. Snimak recepta kod
-- `away` je jelo pre promene, da može da se vrati.
alter table public.meal_plan_entries
  add column kind text not null default 'cook' check (kind in ('cook', 'away')),
  add column away_reason text check (away_reason in ('restaurant', 'visiting', 'skip')),
  add column away_note text check (char_length(away_note) between 1 and 80),
  add constraint meal_plan_entries_away_check check (
    case kind
      when 'away' then away_reason is not null
      else away_reason is null and away_note is null
    end
  );
