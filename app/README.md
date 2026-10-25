# app/ (Member A)

Flutter app for Android and web: citizens use it on their phones, officials use the same build as a web dashboard.

## Run it

```bash
cd app
flutter pub get
flutter run -d chrome            # web dashboard
flutter run                      # Android phone or emulator
```

It connects to the team Supabase project out of the box. The anon key in `lib/config.dart` is public by design; row level security protects the data. Never put the service role key in the app.

To use Member C's API (Granite complaints, PDF, email, Granite assistant), start `api/` and pass its URL:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Without `API_BASE_URL`, every feature still works directly on Supabase: template complaints in English and Hindi, the email opens in your mail app, the built-in assistant answers from map data, and scores are recomputed by the `refresh_city_score` SQL function. If the API is set but unreachable, the app falls back to the same path.

## Screens

| Tab | Who | What |
| --- | --- | --- |
| Map | Everyone | All of India down to street level. City bubbles with site counts, red pins per dump, outlines from zoom 13, ward boundaries, FIRMS fire points, satellite toggle, filters (near water, fire risk, not on any government record) and the pitch line "AI found N dumps in X. M are not on any government record." Updates live when the pipeline writes. |
| Site page | Everyone | Facts, fire risk, the before/after slider over each satellite pass, fire hotspots, complaints, clean-up checks. Officers also change status, draft a complaint and check clean-up. |
| Complaint | Officers | Draft (editable) -> approve -> send to the ward officer -> close. |
| Scores | Everyone | "Cleanliness from space" leaderboard with the four score parts. Officers can recompute. |
| Report | Signed-in citizens | Tap the map, add a note and photo. The report is matched to a site within 150 m or flagged for review. "My reports" shows its status. |
| Assistant | Everyone | Plain-language questions in English or Hindi, answered only from Drishti data, with links to the sites. |
| Officials | Officers, board, admins | Review citizen reports, all complaints, queue pipeline runs for Member B's worker, verify all sent complaints, and (admins) change user roles. |
| Profile | Everyone | Sign in or sign up, name, English/Hindi. |

Roles: `citizen` (default), `officer`, `board` (read-only staff), `admin`. Make the first admin in the Supabase SQL editor:

```sql
update profiles set role = 'admin' where email = 'you@example.com';
```

After that, admins change roles from the Officials > Users tab.

## Code

- `lib/services/drishti_repo.dart` every Supabase query (screens never name tables)
- `lib/services/action_engine.dart` the officer workflow, using the API when present
- `lib/services/api_client.dart` Member C's endpoints
- `lib/services/complaint_drafter.dart`, `local_assistant.dart`, `verification_logic.dart` the no-API fallbacks, matching the API's rules
- `lib/l10n/strings.dart` English and Hindi strings
- `lib/screens/`, `lib/widgets/`, `lib/models/`

## Tests

```bash
flutter analyze
flutter test                                 # unit tests
DRISHTI_LIVE=1 E2E_PASSWORD=... E2E_CITIZEN=... E2E_OFFICER=... E2E_ADMIN=... \
  flutter test test/live_supabase_test.dart  # end to end against Supabase
```

The live test signs in as a citizen, an officer and an admin and runs every flow: map reads, photo upload, report matching, the complaint lifecycle, verification, scores, pipeline queue, and the role rules.
