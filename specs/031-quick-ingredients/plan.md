# Plan

Grana iz origin/main. Proširiti postojeći suggestRecipes opcionim selectedIngredients. Validirati 1–80 znakova po nazivu, najviše tri različita ključa potvrđenog rečnika v1. Bez izbora isti algoritam i izlaz. Sa izborom kandidat može ući i bez zalihe, ako ima stvarno korišćeni izabrani sastojak; broj različitih pogođenih sastojaka je prvi kriterijum, pa postojeći comparator. Jedan poziv istog demandFor/allocateSupply računa količine, porcije i raspoložive rezerve. Metapodaci izbora ne postaju Supply niti menjaju missingMicros.

UseFirstScreen drži privremen izbor i uključuje ga u isti poziv; nova mala proširiva kontrola za unos/chipove. SuggestionCard pokazuje broj poklapanja i jasno traži proveru za izabranu namirnicu bez brojčanog pokrića, uz količinu potrebnu receptu. Bez novih zavisnosti, šeme ili korisničkih upisa.

## Constitution Check I–IX
Srpski Latin; postojeći lokalni recepti i Ostava, bez upisa; bez AI i ključeva; domen test-first (prazna Ostava, rangiranje, sinonimi, duplikati, jedinice, porcije, rok i rezervacije), widget testovi read-only toka i postojećih susednih funkcija; telefon/široki ekran/2×; jedna funkcija na svojoj grani sa spec-om; format/analyze/test hook, ceo skup testova i macOS build.
