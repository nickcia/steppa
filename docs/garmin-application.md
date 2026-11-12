# Garmin Connect Developer Program: Starter access request

Answers for https://www.garmin.com/en-US/forms/StarterGarminConnectDeveloperAccess/. Fields with personal details
(contact, email, address) are left for you to fill in.

## Organisation

- **Company name:** the form asks for a legal company name. If you don't have a registered business, use your
  own legal name as a sole proprietor, e.g. "Nicholas Cianfaglione (TrackStar)". Don't invent a company.
- **Company website:** https://github.com/nickcia/trackstar
- **Privacy policy URL:** https://github.com/nickcia/trackstar/blob/main/PRIVACY.md (update it to cover Garmin and the
  server before Garmin users can connect; see the last section).
- **Contact name / job title:** you; e.g. "Founder and developer".

## Dropdowns

- **Primary business service:** Coaching & Training Programs
- **Industry:** Fitness & Wellness
- **APIs:** Training API, Activity API
- **Connected Garmin users in 12 months:** 100-1000
- **Already in contact with Garmin:** No

## Overview of the application, the user experience and how the APIs will be used

TrackStar is a free, open-source running coach for iPhone. It builds a training plan for a race (5K to marathon)
and adapts it to the runs the athlete actually does.

With Garmin Connect, an athlete taps "Connect Garmin" once in TrackStar and signs in with Garmin. From then on:

- Training API: TrackStar sends the athlete's upcoming planned workouts (warm-up, intervals at target paces,
  cool-down) to their Garmin Connect calendar, and keeps them updated as the plan adapts, so the structured workout
  is on their watch on the right day.
- Activity API: when the athlete finishes a run on their Garmin watch, TrackStar receives the activity (time,
  distance, pace, heart rate and the recording) to tick off the planned workout, show the run's analysis in the app,
  and adjust the coming weeks.

Only running activities that relate to the athlete's plan are used, only for that athlete, inside the app. The
athlete can disconnect at any time in TrackStar's settings, which revokes access and deletes their Garmin data
from our service.

## Business model

TrackStar is free, with no ads, subscriptions or in-app purchases, and its source code is public (open source).
It is built and run by an independent developer. No user data is sold, shared or used for advertising, and Garmin
data is never used to train AI models. If a paid version is ever offered, Garmin data would still only be used to
provide the features described above.

## Third parties that will process or store Garmin device-sourced data

- Cloudflare (Workers and D1): hosts TrackStar's small server, which completes the Garmin sign-in, sends planned
  workouts to the Training API, and receives activity notifications. It holds an athlete's Garmin tokens and their
  new activities only until the athlete's phone collects them, then deletes the activity data.
- Apple (on-device only): activity data is stored on the athlete's iPhone. TrackStar's optional coach uses Apple
  Intelligence's on-device model, which runs entirely on the iPhone; no Garmin data is sent to Apple or any AI
  provider, and none is used for training.

There are no analytics, advertising or other data processors.

## Before Garmin users can connect

Done (11 November 2026): PRIVACY.md has a Garmin Connect section covering the server, Cloudflare, no AI, and
deletion. Starter access was granted and the TrackStar app created in the developer portal.
