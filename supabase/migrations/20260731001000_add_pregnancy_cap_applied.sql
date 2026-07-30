-- Same independent-cap shape as sleep_cap_applied/injury_cap_applied/
-- load_cap_applied: while pregnant, generate-recommendation never returns
-- push_hard, regardless of trimester.
alter table daily_recommendation add column pregnancy_cap_applied boolean not null default false;
