-- Free-text field paired with the goals 'other' tag, mirroring
-- other_equipment_notes.
alter table users
  add column other_goal_notes text;
