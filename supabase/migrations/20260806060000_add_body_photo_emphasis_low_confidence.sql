-- Distinguishes "analyzed, low confidence" from "never analyzed" so the
-- idempotency cache stops re-billing OpenAI on ambiguous photo pairs.
alter table users add column body_photo_emphasis_low_confidence boolean not null default false;
