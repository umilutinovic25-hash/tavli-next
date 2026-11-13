begin;
select * from no_plan();

select has_column('public', 'shopping_contributions', 'approximate', 'doprinos ima oznaku približno');
select col_type_is('public', 'shopping_contributions', 'approximate', 'boolean', 'oznaka je boolean');
select col_not_null('public', 'shopping_contributions', 'approximate', 'oznaka nije null');
select col_default_is('public', 'shopping_contributions', 'approximate', 'false', 'podrazumevano nije približno');

select has_column('public', 'shopping_items', 'approximate', 'stavka ima oznaku približno');
select col_not_null('public', 'shopping_items', 'approximate', 'oznaka stavke nije null');
select col_default_is('public', 'shopping_items', 'approximate', 'false', 'stavka podrazumevano nije približna');

select * from finish();
rollback;
