-- Izvor je deo postojećeg recepta i podleže istim pravilima domaćinstva.
alter table public.recipes add column source_url text;
