-- Free-text field paired with the equipment 'other' tag, for anything not
-- covered by the fixed EquipmentTag list.
alter table users
  add column other_equipment_notes text;
