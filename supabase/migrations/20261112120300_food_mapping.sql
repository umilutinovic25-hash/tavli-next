-- 036 (SC-003): jednokratno mapiranje postojećih podataka na zajednički
-- katalog. Namirnica se postavlja samo po tačnom aliasu (posle normalizacije);
-- sopstveni aliasi domaćinstva, postojeći izbor osobe i tekst (name,
-- quantity, unit) se ne diraju, kao ni snimci (recipe_versions,
-- shopping_sources, recipe_snapshot). touch_updated_at podiže updated_at, pa
-- uređaji preuzimaju mapirane redove; bez auth.uid() updated_by ostaje isti.
-- Funkcija je posebna da bi pgTAP mogao da je testira; ponovno pokretanje
-- menja samo redove kojima nešto nedostaje.
create or replace function private.map_food_ids()
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.recipes r
     set ingredients = m.mapped
    from (
      select r2.id,
             jsonb_agg(
               case
                 when jsonb_typeof(e.v) = 'object'
                      and coalesce(btrim(e.v->>'foodId'), '') = ''
                      and a.food_id is not null
                   then e.v || jsonb_build_object('foodId', a.food_id)
                 else e.v
               end
               order by e.ord) as mapped
        from public.recipes r2
       cross join lateral jsonb_array_elements(r2.ingredients) with ordinality as e(v, ord)
        left join public.food_aliases a
          on a.household_id is null
         and jsonb_typeof(e.v) = 'object'
         and a.alias = private.normalized(e.v->>'name')
       where jsonb_typeof(r2.ingredients) = 'array'
       group by r2.id
    ) m
   where m.id = r.id
     and m.mapped is distinct from r.ingredients;

  update public.pantry_items p
     set food_id = a.food_id
    from public.food_aliases a
   where p.food_id is null
     and a.household_id is null
     and a.alias = private.normalized(p.name);

  update public.shopping_items s
     set food_id = a.food_id
    from public.food_aliases a
   where s.food_id is null
     and a.household_id is null
     and a.alias = private.normalized(s.name);
end;
$$;

revoke execute on function private.map_food_ids() from public, anon, authenticated;

select private.map_food_ids();
