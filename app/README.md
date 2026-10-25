# app/ (Member A)

Flutter app for Android and web: citizens use it on their phones, officials use the same build as a web dashboard (A-23, published to GitHub Pages by `.github/workflows/app-web.yml`).

## Run it

```bash
cd app
flutter pub get
flutter run -d chrome            # web dashboard
flutter run                      # Android phone or emulator
```

It connects to the team Supabase project out of the box. The anon key in `lib/config.dart` is public by design; row level security protects the data. Never put the service role key in the app.

To use Member C's API (Granite complaints, PDF, email, Granite assistant), pass its URL:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Without `API_BASE_URL` (or when the API is down, N-15) every feature still works directly on Supabase: template complaints in English and Hindi, the letter opens in your mail app, the built-in assistant answers from map data, and scores are recomputed by the `refresh_city_score` SQL function.

## Accounts

- Sign in with a 6-digit code sent by email (A-08); a new email gets a citizen account. On first sign-in you pick your home city and language. Only an admin can make someone an officer, board member or admin (Review > Users).
- Demo accounts for each role (citizen, officer, board, admin) sign in with a password ("Use a password instead"). Ask Member A for the logins; they are not in the repo.

## Tabs by role (A-09)

| Tab | Who | What |
| --- | --- | --- |
| Map | everyone | India down to street level. City bubbles, clustered pins coloured by status and sized by area, outlines from zoom 13, ward boundaries, FIRMS fire points. Toggles: satellite/street, sites, fires, wards. Combined filters: status, ward, first seen, near water, not on a government record, fire risk threshold, with a live count. The pitch line "AI found N dumps in X. M are not on any government record." Updates live; opens offline with the last loaded data. |
| Site page | everyone | Facts, confidence, fire risk, the before/after slider over each satellite pass (from `GET /sites/{id}/timeline` when the API is up), fire hotspots, complaints, clean-up checks. Officers change status, dismiss as a false positive with a reason, draft complaints, check clean-up, and see citizen reports for the site. |
| Scores | everyone | "Cleanliness from space" leaderboard with the four score parts and a monthly trend. Officers can recompute. |
| Report | signed in | Pin starts at your GPS position (tap the map to move it), note, camera or gallery photo. The photo is re-encoded without EXIF and stored privately; the report is matched to a site within 150 m or flagged for review. |
| Assistant | everyone | Questions in English or Hindi, answered only from Drishti data; "Show on map" highlights the sites. |
| Complaints | officer, board, admin | All complaints, filtered by status and ward; an officer with a home city sees only that city. Draft -> approve -> send -> close. |
| Pipeline | admin | Queue a detection or fire run for Member B's worker, see run status, verify all sent complaints. |
| Review | admin | New detections to confirm or dismiss, citizen reports to link or reject, user roles and home cities. |
| Profile | everyone | Sign in, name, language (one per ARB file), data credits (N-24). |

## Code

- `lib/services/drishti_repo.dart` every Supabase query, the offline cache, photo upload
- `lib/services/action_engine.dart` the officer workflow, using the API when present
- `lib/services/api_client.dart` Member C's endpoints
- `lib/services/complaint_drafter.dart`, `local_assistant.dart`, `verification_logic.dart` the no-API fallbacks, matching the API's rules
- `lib/l10n/app_en.arb`, `app_hi.arb` the UI text (A-10). Add a language by adding `app_<code>.arb`; `flutter gen-l10n` runs on build.
- `lib/screens/`, `lib/widgets/`, `lib/models/`

## Tests

```bash
flutter analyze
flutter test test/widget_test.dart           # unit tests
DRISHTI_LIVE=1 E2E_PASSWORD=... E2E_CITIZEN=... E2E_OFFICER=... E2E_ADMIN=... \
  flutter test test/live_supabase_test.dart  # end to end against Supabase
```

The live test signs in as a citizen, an officer and an admin and runs every flow: map reads, private photo upload with EXIF removed, report matching, the complaint lifecycle, verification, scores, the pipeline queue, realtime (under 5 s), the audit trigger, dismiss, detection review, and the role rules. It leaves test rows behind; delete them afterwards.
