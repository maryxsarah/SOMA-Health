-- "Add to today's plan" makes an AI-generated plan the day's committed
-- plan (distinct from just having been generated/previewed) -- see
-- generate-workout-plan/generate-gym-workout and GymPhotoWorkoutView /
-- RecommendationDetailView's "Add to today's plan" action.
alter table ai_workout_plan
  add column added_to_plan boolean not null default false,
  add column source text not null default 'suggestion' check (source in ('suggestion', 'gym_photo')),
  add column added_at timestamptz;

-- Counts real AI generations per user per day, independent of
-- ai_workout_plan's single-row-per-day cache -- a different equipment edit
-- or a different suggestion title is a cache MISS (a genuinely new
-- generation) even though ai_workout_plan only ever keeps the latest.
create table ai_generation_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  date date not null,
  source text not null check (source in ('suggestion', 'gym_photo')),
  created_at timestamptz not null default now()
);
create index ai_generation_log_user_date_idx on ai_generation_log(user_id, date);

-- Client-reported (via SubscriptionManager.refreshEntitlement), not
-- cryptographically verified -- same trust model this app already applies
-- to its main paywall gate (HomeView.hasDetailAccess trusts client-side
-- subscriptionManager.isSubscribed with no server-side receipt validation).
-- A cost-control soft limit, not a security boundary.
alter table users add column subscription_tier text not null default 'free' check (subscription_tier in ('free', 'monthly', 'annual'));
