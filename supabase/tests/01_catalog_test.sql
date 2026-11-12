-- Svaka tabela u `public` ima RLS, anon nema nikakva prava, authenticated
-- ima tačno prava iz contracts/server-schema.md. Hvata i buduće tabele.
begin;
select plan(7);

select is(
  array(select c.relname::text from pg_class c
        where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
          and not c.relrowsecurity order by 1),
  array[]::text[],
  'svaka tabela u public ima RLS'
);

select is(
  array(select c.relname::text from pg_class c
        where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm')
          and has_table_privilege('anon', c.oid,
                'select,insert,update,delete,truncate,references,trigger')
        order by 1),
  array[]::text[],
  'anon nema prava ni na jednoj tabeli u public'
);

select is(
  array(select c.relname || ':' || p from pg_class c,
          unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p
        where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm')
          and has_table_privilege('authenticated', c.oid, p)
        order by 1),
  array[
    'allergens:select',
    'cook_soon_items:delete', 'cook_soon_items:insert', 'cook_soon_items:select', 'cook_soon_items:update',
    'day_rules:delete', 'day_rules:insert', 'day_rules:select', 'day_rules:update',
    'day_time_budgets:delete', 'day_time_budgets:insert', 'day_time_budgets:select', 'day_time_budgets:update',
    'deletions:select',
    'food_aliases:insert', 'food_aliases:select', 'food_aliases:update',
    'food_allergens:delete', 'food_allergens:insert', 'food_allergens:select', 'food_allergens:update',
    'food_conversions:insert', 'food_conversions:select', 'food_conversions:update',
    'foods:insert', 'foods:select', 'foods:update',
    'household_invites:select', 'household_members:select', 'household_preferences:delete', 'household_preferences:insert', 'household_preferences:select', 'household_preferences:update', 'households:select',
    'meal_plan_entries:delete', 'meal_plan_entries:insert', 'meal_plan_entries:select', 'meal_plan_entries:update',
    'meal_plans:delete', 'meal_plans:insert', 'meal_plans:select', 'meal_plans:update',
    'member_allergies:delete', 'member_allergies:insert', 'member_allergies:select', 'member_allergies:update',
    'pantry_items:delete', 'pantry_items:insert', 'pantry_items:select', 'pantry_items:update',
    'profiles:select',
    'ratings:delete', 'ratings:insert', 'ratings:select', 'ratings:update',
    'recipe_versions:delete', 'recipe_versions:insert', 'recipe_versions:select', 'recipe_versions:update',
    'recipes:delete', 'recipes:insert', 'recipes:select', 'recipes:update',
    'saved_recipe_searches:delete', 'saved_recipe_searches:insert', 'saved_recipe_searches:select', 'saved_recipe_searches:update',
    'shopping_contributions:delete', 'shopping_contributions:insert', 'shopping_contributions:select', 'shopping_contributions:update',
    'shopping_items:delete', 'shopping_items:insert', 'shopping_items:select', 'shopping_items:update',
    'shopping_lists:delete', 'shopping_lists:insert', 'shopping_lists:select', 'shopping_lists:update',
    'shopping_sources:delete', 'shopping_sources:insert', 'shopping_sources:select', 'shopping_sources:update',
    'supply_allocations:delete', 'supply_allocations:insert', 'supply_allocations:select', 'supply_allocations:update',
    'taste_profiles:delete', 'taste_profiles:insert', 'taste_profiles:select', 'taste_profiles:update',
    'week_templates:delete', 'week_templates:insert', 'week_templates:select', 'week_templates:update'
  ],
  'authenticated ima tačno dogovorena prava na tabelama'
);

select is(
  array(select a.attname::text from pg_attribute a
        where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and not a.attisdropped
          and has_column_privilege('authenticated', 'public.profiles'::regclass, a.attname, 'update')
        order by 1),
  array['display_name'],
  'u profiles authenticated menja samo display_name'
);

select is(
  array(select p.proname::text from pg_proc p
        where p.pronamespace = 'public'::regnamespace
          and has_function_privilege('anon', p.oid, 'execute')),
  array[]::text[],
  'anon ne izvršava nijednu funkciju u public'
);

select is(
  array(select n.nspname || '.' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'private')
          and has_function_privilege('authenticated', p.oid, 'execute')
        order by 1),
  array['private.is_household_owner', 'private.is_member', 'private.is_text_list', 'private.normalized', 'public.create_household_invite', 'public.household_member_list', 'public.leave_household', 'public.redeem_household_invite', 'public.remove_household_member', 'public.transfer_household_ownership'],
  'authenticated izvršava samo dogovorene funkcije'
);

select is(
  (select public from storage.buckets where id = 'recipe-photos'),
  false,
  'bucket recipe-photos je privatan'
);

select * from finish();
rollback;
