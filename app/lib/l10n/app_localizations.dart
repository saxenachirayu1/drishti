import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('hi')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Drishti'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'India\'s garbage, seen from space'**
  String get tagline;

  /// No description provided for @map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get map;

  /// No description provided for @scores.
  ///
  /// In en, this message translates to:
  /// **'Scores'**
  String get scores;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @assistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistant;

  /// No description provided for @officials.
  ///
  /// In en, this message translates to:
  /// **'Officials'**
  String get officials;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @allIndia.
  ///
  /// In en, this message translates to:
  /// **'All India'**
  String get allIndia;

  /// No description provided for @satellite.
  ///
  /// In en, this message translates to:
  /// **'Satellite'**
  String get satellite;

  /// No description provided for @streets.
  ///
  /// In en, this message translates to:
  /// **'Streets'**
  String get streets;

  /// No description provided for @fires.
  ///
  /// In en, this message translates to:
  /// **'Fires'**
  String get fires;

  /// No description provided for @wards.
  ///
  /// In en, this message translates to:
  /// **'Wards'**
  String get wards;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @nearWater.
  ///
  /// In en, this message translates to:
  /// **'Near water'**
  String get nearWater;

  /// No description provided for @highFireRisk.
  ///
  /// In en, this message translates to:
  /// **'High fire risk'**
  String get highFireRisk;

  /// No description provided for @notOnRecord.
  ///
  /// In en, this message translates to:
  /// **'Not on any government record'**
  String get notOnRecord;

  /// No description provided for @onRecord.
  ///
  /// In en, this message translates to:
  /// **'On a government record'**
  String get onRecord;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @somethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWrong;

  /// No description provided for @nothingHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get nothingHere;

  /// No description provided for @site.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get site;

  /// No description provided for @ward.
  ///
  /// In en, this message translates to:
  /// **'Ward'**
  String get ward;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get area;

  /// No description provided for @firstSeen.
  ///
  /// In en, this message translates to:
  /// **'First seen'**
  String get firstSeen;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeen;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @fireRisk.
  ///
  /// In en, this message translates to:
  /// **'Fire risk'**
  String get fireRisk;

  /// No description provided for @confidence.
  ///
  /// In en, this message translates to:
  /// **'Model confidence'**
  String get confidence;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps'**
  String get openInMaps;

  /// No description provided for @officer.
  ///
  /// In en, this message translates to:
  /// **'Ward officer'**
  String get officer;

  /// No description provided for @timeline.
  ///
  /// In en, this message translates to:
  /// **'Growth over time'**
  String get timeline;

  /// No description provided for @timelineHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the slider to see the site in each satellite pass.'**
  String get timelineHint;

  /// No description provided for @firstSighting.
  ///
  /// In en, this message translates to:
  /// **'first sighting'**
  String get firstSighting;

  /// No description provided for @sinceFirst.
  ///
  /// In en, this message translates to:
  /// **'since first seen'**
  String get sinceFirst;

  /// No description provided for @noDetections.
  ///
  /// In en, this message translates to:
  /// **'No detections yet'**
  String get noDetections;

  /// No description provided for @fireEvents.
  ///
  /// In en, this message translates to:
  /// **'Fire hotspots (NASA FIRMS)'**
  String get fireEvents;

  /// No description provided for @complaints.
  ///
  /// In en, this message translates to:
  /// **'Complaints'**
  String get complaints;

  /// No description provided for @draftComplaint.
  ///
  /// In en, this message translates to:
  /// **'Draft complaint'**
  String get draftComplaint;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Complaint language'**
  String get chooseLanguage;

  /// No description provided for @complaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get complaint;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send to ward officer'**
  String get send;

  /// No description provided for @closeComplaint.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeComplaint;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @openPdf.
  ///
  /// In en, this message translates to:
  /// **'Open PDF'**
  String get openPdf;

  /// No description provided for @emailOpened.
  ///
  /// In en, this message translates to:
  /// **'Marked as sent. Your email app has the letter ready.'**
  String get emailOpened;

  /// No description provided for @verification.
  ///
  /// In en, this message translates to:
  /// **'Clean-up checks'**
  String get verification;

  /// No description provided for @checkCleanup.
  ///
  /// In en, this message translates to:
  /// **'Check clean-up now'**
  String get checkCleanup;

  /// No description provided for @changeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change status'**
  String get changeStatus;

  /// No description provided for @statusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Status updated'**
  String get statusUpdated;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a dump'**
  String get reportTitle;

  /// No description provided for @reportHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the map where the waste is, add a note and a photo.'**
  String get reportHint;

  /// No description provided for @tapToPlace.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place the pin'**
  String get tapToPlace;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @notePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What did you see? e.g. garbage burning near the canal'**
  String get notePlaceholder;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get submit;

  /// No description provided for @reportMatched.
  ///
  /// In en, this message translates to:
  /// **'Thanks! This matches a site we already track'**
  String get reportMatched;

  /// No description provided for @reportFlagged.
  ///
  /// In en, this message translates to:
  /// **'Thanks! An official will review this new location.'**
  String get reportFlagged;

  /// No description provided for @myReports.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get myReports;

  /// No description provided for @signInToReport.
  ///
  /// In en, this message translates to:
  /// **'Sign in to report a dump.'**
  String get signInToReport;

  /// No description provided for @leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Cleanliness from space'**
  String get leaderboard;

  /// No description provided for @scoreHint.
  ///
  /// In en, this message translates to:
  /// **'Score out of 100, higher is cleaner. Based on active sites, burning, time to clear and verified clean-ups.'**
  String get scoreHint;

  /// No description provided for @recompute.
  ///
  /// In en, this message translates to:
  /// **'Recompute'**
  String get recompute;

  /// No description provided for @activeSites.
  ///
  /// In en, this message translates to:
  /// **'Active sites'**
  String get activeSites;

  /// No description provided for @burnEvents.
  ///
  /// In en, this message translates to:
  /// **'Burn events'**
  String get burnEvents;

  /// No description provided for @daysToClear.
  ///
  /// In en, this message translates to:
  /// **'Median days to clear'**
  String get daysToClear;

  /// No description provided for @verifiedCleared.
  ///
  /// In en, this message translates to:
  /// **'Verified cleared'**
  String get verifiedCleared;

  /// No description provided for @partActive.
  ///
  /// In en, this message translates to:
  /// **'Few active sites (40)'**
  String get partActive;

  /// No description provided for @partBurn.
  ///
  /// In en, this message translates to:
  /// **'Little burning (25)'**
  String get partBurn;

  /// No description provided for @partClear.
  ///
  /// In en, this message translates to:
  /// **'Quick clean-up (20)'**
  String get partClear;

  /// No description provided for @partVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified cleared (15)'**
  String get partVerified;

  /// No description provided for @askAnything.
  ///
  /// In en, this message translates to:
  /// **'Ask about dumps, wards, fires or scores'**
  String get askAnything;

  /// No description provided for @assistantHint.
  ///
  /// In en, this message translates to:
  /// **'Answers come only from Drishti data.'**
  String get assistantHint;

  /// No description provided for @anyCity.
  ///
  /// In en, this message translates to:
  /// **'All cities'**
  String get anyCity;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Citizen reports'**
  String get reports;

  /// No description provided for @pipeline.
  ///
  /// In en, this message translates to:
  /// **'Pipeline'**
  String get pipeline;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @markMatched.
  ///
  /// In en, this message translates to:
  /// **'Link to site'**
  String get markMatched;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @pickSite.
  ///
  /// In en, this message translates to:
  /// **'Link to which site?'**
  String get pickSite;

  /// No description provided for @queueRun.
  ///
  /// In en, this message translates to:
  /// **'Queue run'**
  String get queueRun;

  /// No description provided for @detectRun.
  ///
  /// In en, this message translates to:
  /// **'Detect dumps (Sentinel-2)'**
  String get detectRun;

  /// No description provided for @firesRun.
  ///
  /// In en, this message translates to:
  /// **'Fire layer (NASA FIRMS)'**
  String get firesRun;

  /// No description provided for @runQueued.
  ///
  /// In en, this message translates to:
  /// **'Run queued. Member B\'s worker will pick it up.'**
  String get runQueued;

  /// No description provided for @verifyAll.
  ///
  /// In en, this message translates to:
  /// **'Verify all sent complaints'**
  String get verifyAll;

  /// No description provided for @verifiedCount.
  ///
  /// In en, this message translates to:
  /// **'sites checked'**
  String get verifiedCount;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get signUp;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get noAccount;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Have an account? Sign in'**
  String get haveAccount;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @apiMode.
  ///
  /// In en, this message translates to:
  /// **'Connected to the Drishti API (Granite)'**
  String get apiMode;

  /// No description provided for @localMode.
  ///
  /// In en, this message translates to:
  /// **'Running directly on Supabase (template complaints, built-in assistant)'**
  String get localMode;

  /// No description provided for @staffOnly.
  ///
  /// In en, this message translates to:
  /// **'For ward officers and admins'**
  String get staffOnly;

  /// No description provided for @legend.
  ///
  /// In en, this message translates to:
  /// **'Legend'**
  String get legend;

  /// No description provided for @foundLine.
  ///
  /// In en, this message translates to:
  /// **'AI found {n} dumps in {place}. {m} are not on any government record.'**
  String foundLine(int n, int m, String place);

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusComplaintSent.
  ///
  /// In en, this message translates to:
  /// **'Complaint sent'**
  String get statusComplaintSent;

  /// No description provided for @statusCleanupReported.
  ///
  /// In en, this message translates to:
  /// **'Clean-up reported'**
  String get statusCleanupReported;

  /// No description provided for @statusCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get statusCleared;

  /// No description provided for @statusDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get statusDismissed;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get statusSent;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @statusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get statusNew;

  /// No description provided for @statusMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get statusMatched;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// No description provided for @statusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get statusRunning;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get statusDone;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @resultStillPresent.
  ///
  /// In en, this message translates to:
  /// **'Still present'**
  String get resultStillPresent;

  /// No description provided for @resultShrinking.
  ///
  /// In en, this message translates to:
  /// **'Shrinking'**
  String get resultShrinking;

  /// No description provided for @resultCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get resultCleared;

  /// No description provided for @roleCitizen.
  ///
  /// In en, this message translates to:
  /// **'Citizen'**
  String get roleCitizen;

  /// No description provided for @roleOfficer.
  ///
  /// In en, this message translates to:
  /// **'Ward officer'**
  String get roleOfficer;

  /// No description provided for @roleBoard.
  ///
  /// In en, this message translates to:
  /// **'Pollution control board'**
  String get roleBoard;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Email me a sign-in code'**
  String get sendCode;

  /// No description provided for @codeSent.
  ///
  /// In en, this message translates to:
  /// **'We emailed you a 6-digit code.'**
  String get codeSent;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify and sign in'**
  String get verify;

  /// No description provided for @usePassword.
  ///
  /// In en, this message translates to:
  /// **'Use a password instead'**
  String get usePassword;

  /// No description provided for @useCode.
  ///
  /// In en, this message translates to:
  /// **'Use an email code instead'**
  String get useCode;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Drishti'**
  String get welcome;

  /// No description provided for @setupHint.
  ///
  /// In en, this message translates to:
  /// **'Pick your city and language. You start as a citizen; an admin can make you an officer.'**
  String get setupHint;

  /// No description provided for @homeCity.
  ///
  /// In en, this message translates to:
  /// **'Home city'**
  String get homeCity;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @sitesLayer.
  ///
  /// In en, this message translates to:
  /// **'Sites'**
  String get sitesLayer;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @anyWard.
  ///
  /// In en, this message translates to:
  /// **'All wards'**
  String get anyWard;

  /// No description provided for @firstSeenSince.
  ///
  /// In en, this message translates to:
  /// **'First seen'**
  String get firstSeenSince;

  /// No description provided for @anyTime.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get anyTime;

  /// No description provided for @last30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30;

  /// No description provided for @last90.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get last90;

  /// No description provided for @last180.
  ///
  /// In en, this message translates to:
  /// **'Last 6 months'**
  String get last180;

  /// No description provided for @fireRiskAbove.
  ///
  /// In en, this message translates to:
  /// **'Fire risk at least'**
  String get fireRiskAbove;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @sitesShown.
  ///
  /// In en, this message translates to:
  /// **'sites shown'**
  String get sitesShown;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @offlineData.
  ///
  /// In en, this message translates to:
  /// **'Offline: showing the last loaded data'**
  String get offlineData;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss as false positive'**
  String get dismiss;

  /// No description provided for @dismissReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get dismissReason;

  /// No description provided for @dismissHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. construction site, not waste'**
  String get dismissHint;

  /// No description provided for @dismissedBecause.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get dismissedBecause;

  /// No description provided for @useMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get useMyLocation;

  /// No description provided for @locationOff.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable. Tap the map to place the pin.'**
  String get locationOff;

  /// No description provided for @reportsHere.
  ///
  /// In en, this message translates to:
  /// **'Citizen reports here'**
  String get reportsHere;

  /// No description provided for @trend.
  ///
  /// In en, this message translates to:
  /// **'Monthly trend'**
  String get trend;

  /// No description provided for @showOnMap.
  ///
  /// In en, this message translates to:
  /// **'Show on map'**
  String get showOnMap;

  /// No description provided for @newDetections.
  ///
  /// In en, this message translates to:
  /// **'New detections'**
  String get newDetections;

  /// No description provided for @confirmSite.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmSite;

  /// No description provided for @reviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get reviewed;

  /// No description provided for @scenesLabel.
  ///
  /// In en, this message translates to:
  /// **'scenes'**
  String get scenesLabel;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get newLabel;

  /// No description provided for @updatedLabel.
  ///
  /// In en, this message translates to:
  /// **'updated'**
  String get updatedLabel;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About and data credits'**
  String get about;

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
