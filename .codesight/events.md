# Events & Queues

- `reactions:#{talk.slug}` [channel] — `lib/speechwave_web/live/talk_live.ex`
- `slides:#{talk.slug}` [channel] — `lib/speechwave_web/live/talk_live.ex`
- `presenters:#{user.id}` [channel] — `test/speechwave_web/channels/reaction_channel_test.exs`
- `user:#{user.id}:disconnect` [channel] — `test/speechwave_web/live/user_live/settings_test.exs`
