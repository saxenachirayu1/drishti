/// Build-time settings. Override any of them with --dart-define, e.g.
///   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
///
/// The anon key is public by design (row level security protects the data),
/// so it has a default here. The service role key must never be in the app.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ofudjcrzdgltpoyavibr.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9mdWRqY3J6ZGdsdHBveWF2aWJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI4NTcxMzIsImV4cCI6MjEwODQzMzEzMn0.1Y2X2NRVGdO7zKB_K4pSzyoyNDCZ8pJJSNRj0fn0k5A',
  );

  /// Member C's FastAPI service. Empty = the app does everything itself
  /// against Supabase (template complaints, local assistant, SQL score).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// --dart-define=DEMO=true: complaints, tracking, the console and impact run
  /// on sample data in memory (for showing the app on localhost with no
  /// database). The app shows a DEMO banner.
  static const demo = bool.fromEnvironment('DEMO');
}
