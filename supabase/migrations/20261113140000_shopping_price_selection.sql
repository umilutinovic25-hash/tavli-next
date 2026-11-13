-- Potvrđen proizvod i veličina pakovanja prate stavku i njenu postojeću RLS politiku.
alter table public.shopping_items add column price_selection jsonb;
alter table public.shopping_items add constraint shopping_price_selection_object
  check (price_selection is null or (jsonb_typeof(price_selection) = 'object' and pg_column_size(price_selection) <= 4096));
