-- Detalji pripadaju postojećoj stavci i nasleđuju RLS domaćinstva.
-- Fotografija je jedinstven naziv JPEG-a u postojećem privatnom bucket-u.
alter table public.shopping_items
  add column brand text check (char_length(brand) <= 120),
  add column note text check (char_length(note) <= 1000),
  add column photo_path text check (photo_path is null or photo_path ~ '^[a-zA-Z0-9_-]+\.jpg$');
