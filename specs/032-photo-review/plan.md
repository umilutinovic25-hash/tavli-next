# Plan

Grana iz najnovijeg origin/main. Mali domen quantity_review klasifikuje postojeći Ingredient.quantity; ne menja parser, AI upit ili trajni model. AiRecipePreview za fotografiju koristi PhotoRecipeComparison, a tok po nazivu ostaje isti. Poređenje nadograđuje RecipeView opcionim oznakama i callbackom za indeks sastojka. Široki prozor ima dva skrol panela, telefon jedan; PhotoScan i njegove animacije ostaju. Originalni dokument prikazuje se sa BoxFit.contain i fullscreen InteractiveViewer-om.

FromPhotoScreen menja samo otvoreni _result kopiranjem liste sastojaka. Ponovo koristiti privatni editor iz RecipeFormScreen kroz javnu funkciju showRecipeIngredientEditor; opciona stroža validacija važi samo za foto-pregled, da se ne uvodi uzgredna promena ručnog unosa. Neispravne količine blokiraju samo upis/pripremu nabavke foto-pregleda, ne pregled/retry/discard. Opcioni preservePrecision u postojećem formatteru važi za foto-pregled/editor: 0,001 g ostaje 0,001 g; podrazumevani prikazi nisu promenjeni. Bez nove šeme, paketa ili novih formata podataka.

## Constitution Check I–IX
Srpski Latin; isti lokalni recept i outbox tek na potvrdu; AI kroz postojeći AIRouter; bez ključeva; domen test-first i widget testovi poređenja/ispravke/nepoznato/neispravno/čuvanje/odustajanje, susedni tokovi; telefon/široki ekran/2×; jedna funkcija i spec na svojoj grani; standardni hook, ceo skup testova i macOS build.
