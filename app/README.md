# app/ (Member A)

Flutter app for Android and web.

- `lib/screens/` map, site detail, complaints, report, scores, assistant, admin
- `lib/services/` Supabase and API clients
- `lib/models/` data classes (site, detection, complaint, ...)
- `lib/widgets/` shared UI pieces
- `lib/l10n/` English and Hindi strings

Set up: run `flutter create --platforms=android,web .` inside this folder, then add `supabase_flutter`, `flutter_map` and `flutter_riverpod`.
