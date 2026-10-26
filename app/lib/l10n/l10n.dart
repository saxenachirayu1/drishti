import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// The UI strings for the current language. Text lives in the ARB files next
/// to this one (app_en.arb, app_hi.arb); adding a language is a new ARB file.
typedef S = AppLocalizations;

S stringsFor(String languageCode) => lookupAppLocalizations(Locale(languageCode));

/// Database codes (statuses, results, roles) to display text.
extension CodeLabels on AppLocalizations {
  String status(String code) => switch (code) {
        'active' => statusActive,
        'complaint_sent' => statusComplaintSent,
        'cleanup_reported' => statusCleanupReported,
        'cleared' => statusCleared,
        'dismissed' => statusDismissed,
        'draft' => statusDraft,
        'approved' => statusApproved,
        'sent' => statusSent,
        'closed' => statusClosed,
        'new' => statusNew,
        'matched' => statusMatched,
        'rejected' => statusRejected,
        'queued' => statusQueued,
        'running' => statusRunning,
        'done' => statusDone,
        'failed' => statusFailed,
        _ => code,
      };

  String result(String code) => switch (code) {
        'still_present' => resultStillPresent,
        'shrinking' => resultShrinking,
        'cleared' => resultCleared,
        _ => code,
      };

  String roleName(String code) => switch (code) {
        'citizen' => roleCitizen,
        'officer' => roleOfficer,
        'board' => roleBoard,
        'admin' => roleAdmin,
        _ => code,
      };
}

/// Profile `language` values (brief section 6) to locale codes and back.
String localeForLanguage(String language) => language == 'Hindi' ? 'hi' : 'en';
String languageForLocale(String code) => code == 'hi' ? 'Hindi' : 'English';
