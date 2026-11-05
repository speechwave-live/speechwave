# Dependency Graph

## Most Imported Files (change these carefully)

- `lib/speechwave/accounts_fixtures.ex` — imported by **29** files
- `lib/speechwave_web/conn_case.ex` — imported by **23** files
- `lib/speechwave/accounts.ex` — imported by **22** files
- `lib/speechwave/repo.ex` — imported by **15** files
- `lib/speechwave/talks_fixtures.ex` — imported by **15** files
- `lib/speechwave/data_case.ex` — imported by **13** files
- `lib/speechwave/accounts/scope.ex` — imported by **12** files
- `lib/ex_unit/case.ex` — imported by **12** files
- `lib/speechwave/deletion_log.ex` — imported by **9** files
- `lib/speechwave_web/e2_e_case.ex` — imported by **9** files
- `lib/speechwave/.ex` — imported by **8** files
- `lib/speechwave/accounts/user.ex` — imported by **7** files
- `lib/speechwave/plans.ex` — imported by **6** files
- `lib/speechwave/accounts/.ex` — imported by **5** files
- `lib/speechwave/talks.ex` — imported by **5** files
- `lib/speechwave_web/user_auth.ex` — imported by **5** files
- `lib/speechwave/talks/talk.ex` — imported by **4** files
- `lib/speechwave/talks/.ex` — imported by **3** files
- `lib/speechwave/reactions/reaction.ex` — imported by **3** files
- `lib/speechwave/talks/talk_session.ex` — imported by **3** files

## Import Map (who imports what)

- `lib/speechwave/accounts_fixtures.ex` ← `test/speechwave/accounts/suspicious_user_reaper_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/accounts_test.exs`, `test/speechwave/admin/consent_export_test.exs`, `test/speechwave/admin/stats_test.exs` +24 more
- `lib/speechwave_web/conn_case.ex` ← `test/speechwave_web/components/layouts_test.exs`, `test/speechwave_web/controllers/admin/consent_export_controller_test.exs`, `test/speechwave_web/controllers/error_html_test.exs`, `test/speechwave_web/controllers/error_json_test.exs`, `test/speechwave_web/controllers/page_controller_test.exs` +18 more
- `lib/speechwave/accounts.ex` ← `lib/speechwave/accounts/suspicious_user_reaper.ex`, `lib/speechwave/data_export.ex`, `lib/speechwave_web/channels/reaction_channel.ex`, `lib/speechwave_web/controllers/dev_login_controller.ex`, `lib/speechwave_web/controllers/user_account_controller.ex` +17 more
- `lib/speechwave/repo.ex` ← `lib/speechwave/accounts.ex`, `lib/speechwave/admin/consent_export.ex`, `lib/speechwave/admin/stats.ex`, `lib/speechwave/data_export.ex`, `lib/speechwave/reactions.ex` +10 more
- `lib/speechwave/talks_fixtures.ex` ← `test/e2e/reaction_flow_test.exs`, `test/e2e/session_analytics_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/admin/consent_export_test.exs`, `test/speechwave/admin/stats_test.exs` +10 more
- `lib/speechwave/data_case.ex` ← `test/speechwave/accounts/suspicious_user_reaper_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/accounts_test.exs`, `test/speechwave/admin/consent_export_test.exs`, `test/speechwave/admin/stats_test.exs` +8 more
- `lib/speechwave/accounts/scope.ex` ← `lib/speechwave/data_export.ex`, `lib/speechwave/talks.ex`, `lib/speechwave_web/user_auth.ex`, `scripts/manual_tests/seed_screenshots.exs`, `test/speechwave/data_export_test.exs` +7 more
- `lib/ex_unit/case.ex` ← `test/speechwave/admin/chart_test.exs`, `test/speechwave/admin/csv_test.exs`, `test/speechwave/audience_slots_test.exs`, `test/speechwave/auth_throttle_test.exs`, `test/speechwave/data_export_throttle_test.exs` +7 more
- `lib/speechwave/deletion_log.ex` ← `lib/speechwave/accounts.ex`, `lib/speechwave/admin/stats.ex`, `lib/speechwave/db_backup.ex`, `test/speechwave/accounts/suspicious_user_reaper_test.exs`, `test/speechwave/accounts_delete_test.exs` +4 more
- `lib/speechwave_web/e2_e_case.ex` ← `test/e2e/account_settings_test.exs`, `test/e2e/auth_throttle_test.exs`, `test/e2e/dashboard_test.exs`, `test/e2e/email_consent_test.exs`, `test/e2e/reaction_flow_test.exs` +4 more
