# Events & Queues

- `reactions:#{slug}` [channel] — `lib/speechwave_web/live/talk_live.ex`
- `slides:#{slug}` [channel] — `lib/speechwave_web/live/talk_live.ex`
- `slides:#{talk.slug}` [channel] — `test/speechwave_web/channels/reaction_channel_test.exs`
- `reactions:#{talk.slug}` [channel] — `test/speechwave_web/live/talk_live_test.exs`
- `user:#{user.id}:disconnect` [channel] — `test/speechwave_web/live/user_live/settings_test.exs`
