-- Sport Goal Programs: promote straight to live, skipping the 'beta'
-- self-opt-in stage entirely. Product decision (2026-08-16), overriding
-- O-10's S&C expert review gate knowingly -- see docs/bug-log.md. The
-- beta_optins table/RLS stays in place (harmless, reusable for a future
-- sport added the same internal -> beta -> live way), just nothing
-- references it from the client anymore.
update sports set status = 'live' where status in ('internal', 'beta');
