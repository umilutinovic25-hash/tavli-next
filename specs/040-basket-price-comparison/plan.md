# Plan 040

Bez novih zavisnosti. Drift 18 → 19 dodaje izbor na postojeću stavku, uz server migraciju i postojeće RLS politike. Dio preuzima dva fiksna javna CSV izvora, parsiranje se obavlja u izolatu, i samo važeće cene idu u privremeni model. Ekran je povezan sa postojećom listom, bez izmene podataka o nabavci. Čist obračun koristi osnovne jedinice i pare; za različitu pokrivenost prikazuje međuzbir a ne tvrdnju o najjeftinijoj korpi.

Javni CSV keš se po izvoru čuva u prostoru aplikacije i koristi pri grešci preuzimanja; izbor se upisuje u istu transakciju sa outbox redom. Cene prikazuju datum cenovnika i vreme preuzimanja. Format izvora može se promeniti.
