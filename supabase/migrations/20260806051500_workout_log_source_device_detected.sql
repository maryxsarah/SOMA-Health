-- Widens workout_log.source to also accept 'device_detected' -- a
-- workout HomeView auto-logged from a passively-synced health source
-- (Apple Health, Oura, Whoop) that the user never explicitly logged
-- through the app. Real feedback: a friend did a 2h workout (1229 kcal,
-- captured by Apple Health) and Soma never marked the day done because
-- nothing had been logged into workout_log -- the timeline card showed
-- it, but nothing read that timeline to satisfy "today's workout."
alter table workout_log drop constraint workout_log_source_check;
alter table workout_log add constraint workout_log_source_check
  check (source in ('ai_plan', 'manual', 'device_detected'));
