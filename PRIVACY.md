# Privacy policy

_Last updated: 11 November 2026_

TrackStar is a free, open-source running coach for iPhone. It's built so that your data stays yours.

## The short version

- There are no TrackStar accounts, ads, analytics or tracking.
- Your training plan and progress are stored on your iPhone (and in your own private iCloud, if sync is on).
- Nothing is sent to the developer. The one exception is Garmin Connect, which needs a small TrackStar server
  (see below); it only passes your workouts and runs between Garmin and your iPhone.
- If you choose to connect Intervals.icu, your upcoming workouts are sent to your own Intervals.icu account so
  they can reach your Garmin, COROS, Suunto or Wahoo watch.
- If you choose to connect Garmin Connect, your upcoming workouts go to your Garmin Connect calendar and your
  Garmin runs come back to your iPhone, through TrackStar's server.
- If you choose to connect Strava, runs you record on your iPhone are uploaded to your own Strava account, and your
  recent Strava runs are read on your iPhone to avoid duplicates and give watch runs your plan's name.

## What the app stores

Your training plan, which workouts you've done or skipped, races, and preferences. This is kept on your
iPhone. If iCloud sync is on, it is also kept in your private iCloud database, which only you can read. You can
export all of it as a file and delete it at any time by deleting the app.

## Apple Health

With your permission, the app reads from Apple Health: running workouts and distance (to tick off workouts and
adapt your plan), heart rate, running power and step counts during runs (for run analysis: splits, heart-rate
zones, cadence), and your date of birth (only to estimate your maximum heart rate). The only thing it writes is a
run you record on your iPhone with a guided run (Start): it's saved as a running workout with its distance and
route, so it counts in Health and ticks off your plan. Health data never leaves your iPhone. You can change access in the Health app under Sharing › Apps.

## Apple Watch and reminders

Workouts you send to Apple Watch and workout reminders are handled by iOS on your devices.

## Location, during guided runs only (optional)

When you start a workout on your phone (**Start**), the app asks for your location. It's used only while that run
is in progress: to measure distance and pace, and to keep the countdown and spoken cues going with the screen
locked. The route is kept on your iPhone until the run is saved to Apple Health as part of the workout (if you
allow that), and is never sent anywhere else. Tracking stops when the run ends. If you don't allow it, guided runs still work while
the app is open. You can change this in Settings › TrackStar › Location.

## Calendar (optional)

**Add to Calendar** on a workout opens iOS's own "New Event" sheet, filled in. You choose whether to add it;
the app gets no access to your calendars.

**Show my plan in Calendar** in Settings creates a calendar for your workouts and keeps it up to date. iOS
only allows this with full calendar access, which you're asked for when you turn it on. The app only ever
reads and changes the calendar it created, never your other calendars or events. Turning it off deletes that
calendar.

## The coach (optional)

The coach uses Apple Intelligence's on-device model. Your questions, plan and runs are processed on your iPhone
and are not sent to the developer or to any server, including Apple's cloud. Conversations aren't saved after you
close the coach. You can hide the coach in Settings.

## Intervals.icu (optional)

If you connect Intervals.icu, the app talks directly from your iPhone to Intervals.icu. It:

- **Sends** your upcoming planned workouts (date, name, steps and pace targets) to your Intervals.icu
  calendar, and updates or removes them when your plan changes.
- **Reads** your athlete name and which watch services (Garmin, COROS, Suunto, Wahoo) are linked to your
  Intervals.icu account, and **turns on** workout upload for linked services so workouts reach your watch.

- **Reads** your completed runs (time, distance, heart rate, power, cadence and elevation over the run), so
  runs recorded on Garmin and other watches can tick off workouts and be analysed in the app. These are stored
  on your iPhone.

It does not read your wellness or health data from Intervals.icu. Your sign-in is stored in your
iPhone's Keychain, on this device only. Disconnecting in the app removes its upcoming workouts from your
calendar and deletes the sign-in from your iPhone; you can also revoke access in Intervals.icu under
Settings › Apps. What Intervals.icu does with your data is covered by Intervals.icu's own privacy policy.

## Garmin Connect (optional)

Garmin only lets apps connect through a server, so this is the one feature that uses one: a small TrackStar server
hosted on Cloudflare (Workers and D1 database). There is still no TrackStar account. When you tap **Connect with
Garmin Connect**, your iPhone gets a random ID and key from the server, and you sign in on Garmin's own page. Then:

- **Your Garmin sign-in.** The server stores the access tokens Garmin gives it, encrypted, and your Garmin user ID,
  linked only to that random ID. Your Garmin password never reaches TrackStar.
- **Workouts to your watch.** Your iPhone sends your next two weeks of planned workouts (date, name, description,
  steps and pace targets) to the server, which puts them on your Garmin Connect calendar and updates or removes them
  as your plan changes. The server remembers which Garmin workout belongs to which planned workout, so it can
  update it.
- **Runs back to TrackStar.** When you finish a run on your Garmin device, Garmin sends it to the server: its time,
  distance, pace, heart rate, cadence, power and elevation over the run, and the device name. Other activity types
  are ignored and GPS positions are not kept. The run waits on the server, compressed, until your iPhone collects
  it, and is then deleted from the server (anything not collected within 30 days is deleted anyway). On your
  iPhone it ticks off your planned workout, is shown in your run analysis, and helps adapt your plan, the same as a
  run from Apple Health.

**Who processes it.** Only Cloudflare, which hosts the server, and Garmin. Garmin data is never sold, shared with
anyone else, or used for advertising.

**AI.** Garmin data is not processed by any AI system: TrackStar's optional coach does not see runs that came from
Garmin, and Garmin data is never used to train, evaluate or improve AI models.

**Your control.** Garmin data comes only from runs you record after connecting, and you can see all of it in the
app, on each run. **Disconnect** in Settings revokes TrackStar's access at Garmin
and deletes your sign-in, tracked workouts and any waiting runs from the server; runs already on your iPhone are
deleted with the app. You can also remove TrackStar in Garmin Connect (Settings › Connected Apps), which tells the
server to delete the same data. To ask about or delete anything else, email the address below.

## Strava (optional)

If you connect Strava, the app talks directly from your iPhone to Strava. The one exception is signing in: Strava
requires a secret that can't be kept safely inside an app, so the sign-in passes through TrackStar's server, which
adds it and hands Strava's reply straight back to your iPhone without keeping it.

- **Uploads** runs you record on your iPhone (guided runs) to your Strava account: the route (GPS points with
  times), distance, time, and a title and description from your plan ("Week 5: Threshold · 7 km" and its steps).
  You can turn this off in Settings.
- **Reads** your recent Strava activities (their times, distances, names and descriptions, from the last few days)
  for two things: to spot when your watch recorded the same run as your phone, so it isn't uploaded twice, and to
  find the watch runs that completed a planned workout.
- **Renames** those watch runs with your plan's title, and adds the workout's steps as their description, but only
  while they still have their default name (like "Morning Run") and an empty description. Anything you named or
  wrote yourself is left alone. You can turn this off in Settings.

What's read stays on your iPhone; nothing is sent anywhere else. If you're offline when a run finishes, it waits on
your iPhone and uploads the next time you open the app. Your Strava sign-in is stored in your iPhone's Keychain.
Disconnecting in Settings revokes the app's access and deletes the sign-in and any waiting runs from your iPhone;
you can also revoke access on Strava under Settings › My Apps. What Strava does with your runs is covered by
Strava's own privacy policy, and its privacy settings decide who can see them.

## Crash reports

If TrackStar crashes, iOS gives the app a crash report the next time it opens, and the app asks whether
you'd like to send it. If you say yes, your email app opens with the report attached; nothing is sent unless
you send the email yourself, and if you say no it's deleted. A crash report holds the app and iOS versions,
your iPhone model, and technical details of where in the code the crash happened. It contains no health data,
runs or personal details.

Separately, if you've opted in to sharing analytics with developers in iOS Settings, Apple may share anonymous
crash reports with the developer.

## Children

The app is not directed at children under 13.

## Changes and contact

Changes to this policy are published here, with the date at the top. Questions: email
nickseeya@gmail.com or open an issue on the project's GitHub page.

## Bug reports

"Report a bug" in Settings opens your own email app with a message ready to send: the app version, your
iPhone model and iOS version, and (if you leave it on) a one-line summary of your plan, such as "Half
marathon, 12 weeks, runs on Tue, Thu, Sat, Sun". No health data or runs are included. Nothing is sent
unless you send the email yourself.
