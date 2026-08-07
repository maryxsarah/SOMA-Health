-- Whoop/Oura refresh-token failures (revoked access, expired refresh
-- token) previously failed silently: ensureFreshWhoopToken/
-- ensureFreshOuraToken just returned null and the row sat there
-- unchanged, so the client's local "connected" cache never learned
-- anything was wrong. This column is the signal that closes that gap --
-- set true the moment a refresh attempt fails, cleared the moment a
-- fresh connect (or a later successful refresh) succeeds.
alter table wearable_tokens add column needs_reconnect boolean not null default false;
