# Strava API review

What to send with Strava's API program form (https://share.hsforms.com/1VXSwPUYqSH6IxK0y51FjHwcnkd8) to connect
more than 10 athletes. Before that, raise the limit to 10 yourself on strava.com/settings/api.

## Screenshots

- `settings-connect.png`: Settings › Strava, with the official "Connect with Strava" button and the "Compatible with
  Strava" mark.
- Take these two on a phone that's connected to Strava:
  - Settings › Strava when connected (athlete name, Upload phone runs, Name watch runs after your plan).
  - The end of a guided run, showing "On Strava." and the "View on Strava" link.

TrackStar doesn't display any Strava data: it uploads, and reads recent activities only to avoid duplicates and to
title watch runs. Those two screens are every place Strava appears.

## Answers for the form

**App name:** TrackStar
**Client ID:** 295676
**Website:** https://github.com/nickcia/trackstar
**Platform:** iOS (TestFlight beta; App Store later)

**What does your app do?**
TrackStar is a free, open-source running coach for iPhone. It builds a training plan for a race (5K to marathon)
and adapts it to the runs the athlete actually does. It has no accounts: everything runs on the phone, apart from a small server that completes Strava and Garmin sign-ins so the client secret stays out of the app.

**How does it use the Strava API?**
- Uploads runs the athlete records on their iPhone with TrackStar's guided runs (GPX via the uploads endpoint, or a
  manual activity when GPS was off), titled from their plan, for example "Week 5: Threshold · 7 km", with the
  workout's steps in the description.
- Reads the athlete's recent activities (last few days) on the phone, for two things: to skip uploading a phone run
  when their watch already recorded it (no duplicates), and to give watch runs that completed a planned workout the
  plan's title and steps, only while the activity still has its default name and an empty description.
- Scopes: activity:write, activity:read_all. No Strava data is shown to other users, stored off the device, or sent
  to any server; there is no TrackStar server.

**Expected number of athletes:** a small beta at first (tens), growing with an App Store release.

**Brand guidelines:** uses the official "Connect with Strava" button (orange, 48 pt), the "Compatible with Strava"
mark in the Strava settings, and "View on Strava" links in Strava orange, bold. Strava's name and logos are kept
separate from TrackStar's name and icon.
