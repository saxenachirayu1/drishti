/// English and Hindi UI text. `S.of(hindi)` picks one; every screen reads
/// strings from here, so adding a word means adding it to both blocks.
class S {
  const S._(this._m);
  final Map<String, String> _m;

  static S of(bool hindi) => hindi ? hi : en;

  String _t(String k) => _m[k] ?? en._m[k] ?? k;

  String get appName => _t('appName');
  String get tagline => _t('tagline');
  String get map => _t('map');
  String get scores => _t('scores');
  String get report => _t('report');
  String get assistant => _t('assistant');
  String get officials => _t('officials');
  String get profile => _t('profile');
  String get allIndia => _t('allIndia');
  String get satellite => _t('satellite');
  String get streets => _t('streets');
  String get fires => _t('fires');
  String get wards => _t('wards');
  String get filters => _t('filters');
  String get all => _t('all');
  String get nearWater => _t('nearWater');
  String get highFireRisk => _t('highFireRisk');
  String get notOnRecord => _t('notOnRecord');
  String get onRecord => _t('onRecord');
  String get open => _t('open');
  String get retry => _t('retry');
  String get loading => _t('loading');
  String get somethingWrong => _t('somethingWrong');
  String get nothingHere => _t('nothingHere');
  String get site => _t('site');
  String get ward => _t('ward');
  String get city => _t('city');
  String get area => _t('area');
  String get firstSeen => _t('firstSeen');
  String get lastSeen => _t('lastSeen');
  String get change => _t('change');
  String get fireRisk => _t('fireRisk');
  String get confidence => _t('confidence');
  String get location => _t('location');
  String get openInMaps => _t('openInMaps');
  String get officer => _t('officer');
  String get timeline => _t('timeline');
  String get timelineHint => _t('timelineHint');
  String get firstSighting => _t('firstSighting');
  String get sinceFirst => _t('sinceFirst');
  String get noDetections => _t('noDetections');
  String get fireEvents => _t('fireEvents');
  String get complaints => _t('complaints');
  String get draftComplaint => _t('draftComplaint');
  String get chooseLanguage => _t('chooseLanguage');
  String get complaint => _t('complaint');
  String get approve => _t('approve');
  String get send => _t('send');
  String get closeComplaint => _t('closeComplaint');
  String get save => _t('save');
  String get saved => _t('saved');
  String get copy => _t('copy');
  String get copied => _t('copied');
  String get openPdf => _t('openPdf');
  String get emailOpened => _t('emailOpened');
  String get verification => _t('verification');
  String get checkCleanup => _t('checkCleanup');
  String get changeStatus => _t('changeStatus');
  String get statusUpdated => _t('statusUpdated');
  String get reportTitle => _t('reportTitle');
  String get reportHint => _t('reportHint');
  String get tapToPlace => _t('tapToPlace');
  String get note => _t('note');
  String get notePlaceholder => _t('notePlaceholder');
  String get addPhoto => _t('addPhoto');
  String get camera => _t('camera');
  String get gallery => _t('gallery');
  String get submit => _t('submit');
  String get reportMatched => _t('reportMatched');
  String get reportFlagged => _t('reportFlagged');
  String get myReports => _t('myReports');
  String get signInToReport => _t('signInToReport');
  String get leaderboard => _t('leaderboard');
  String get scoreHint => _t('scoreHint');
  String get recompute => _t('recompute');
  String get activeSites => _t('activeSites');
  String get burnEvents => _t('burnEvents');
  String get daysToClear => _t('daysToClear');
  String get verifiedCleared => _t('verifiedCleared');
  String get partActive => _t('partActive');
  String get partBurn => _t('partBurn');
  String get partClear => _t('partClear');
  String get partVerified => _t('partVerified');
  String get askAnything => _t('askAnything');
  String get assistantHint => _t('assistantHint');
  String get anyCity => _t('anyCity');
  String get reports => _t('reports');
  String get pipeline => _t('pipeline');
  String get users => _t('users');
  String get markMatched => _t('markMatched');
  String get reject => _t('reject');
  String get pickSite => _t('pickSite');
  String get queueRun => _t('queueRun');
  String get detectRun => _t('detectRun');
  String get firesRun => _t('firesRun');
  String get runQueued => _t('runQueued');
  String get verifyAll => _t('verifyAll');
  String get verifiedCount => _t('verifiedCount');
  String get role => _t('role');
  String get signIn => _t('signIn');
  String get signUp => _t('signUp');
  String get signOut => _t('signOut');
  String get email => _t('email');
  String get password => _t('password');
  String get fullName => _t('fullName');
  String get noAccount => _t('noAccount');
  String get haveAccount => _t('haveAccount');
  String get language => _t('language');
  String get apiMode => _t('apiMode');
  String get localMode => _t('localMode');
  String get staffOnly => _t('staffOnly');
  String get legend => _t('legend');

  String foundLine(int n, int m, String place) => _t('foundLine')
      .replaceAll('{n}', '$n')
      .replaceAll('{m}', '$m')
      .replaceAll('{place}', place);

  String status(String code) => _t('status_$code');
  String result(String code) => _t('result_$code');
  String roleName(String code) => _t('role_$code');

  static const en = S._({
    'appName': 'Drishti',
    'tagline': "India's garbage, seen from space",
    'map': 'Map',
    'scores': 'Scores',
    'report': 'Report',
    'assistant': 'Assistant',
    'officials': 'Officials',
    'profile': 'Profile',
    'allIndia': 'All India',
    'satellite': 'Satellite',
    'streets': 'Streets',
    'fires': 'Fires',
    'wards': 'Wards',
    'filters': 'Filters',
    'all': 'All',
    'nearWater': 'Near water',
    'highFireRisk': 'High fire risk',
    'notOnRecord': 'Not on any government record',
    'onRecord': 'On a government record',
    'open': 'Open',
    'retry': 'Retry',
    'loading': 'Loading...',
    'somethingWrong': 'Something went wrong',
    'nothingHere': 'Nothing here yet',
    'site': 'Site',
    'ward': 'Ward',
    'city': 'City',
    'area': 'Area',
    'firstSeen': 'First seen',
    'lastSeen': 'Last seen',
    'change': 'Change',
    'fireRisk': 'Fire risk',
    'confidence': 'Model confidence',
    'location': 'Location',
    'openInMaps': 'Open in Google Maps',
    'officer': 'Ward officer',
    'timeline': 'Growth over time',
    'timelineHint': 'Drag the slider to see the site in each satellite pass.',
    'firstSighting': 'first sighting',
    'sinceFirst': 'since first seen',
    'noDetections': 'No detections yet',
    'fireEvents': 'Fire hotspots (NASA FIRMS)',
    'complaints': 'Complaints',
    'draftComplaint': 'Draft complaint',
    'chooseLanguage': 'Complaint language',
    'complaint': 'Complaint',
    'approve': 'Approve',
    'send': 'Send to ward officer',
    'closeComplaint': 'Close',
    'save': 'Save',
    'saved': 'Saved',
    'copy': 'Copy text',
    'copied': 'Copied',
    'openPdf': 'Open PDF',
    'emailOpened': 'Marked as sent. Your email app has the letter ready.',
    'verification': 'Clean-up checks',
    'checkCleanup': 'Check clean-up now',
    'changeStatus': 'Change status',
    'statusUpdated': 'Status updated',
    'reportTitle': 'Report a dump',
    'reportHint': 'Tap the map where the waste is, add a note and a photo.',
    'tapToPlace': 'Tap the map to place the pin',
    'note': 'Note',
    'notePlaceholder': 'What did you see? e.g. garbage burning near the canal',
    'addPhoto': 'Add photo',
    'camera': 'Camera',
    'gallery': 'Gallery',
    'submit': 'Submit report',
    'reportMatched': 'Thanks! This matches a site we already track',
    'reportFlagged': 'Thanks! An official will review this new location.',
    'myReports': 'My reports',
    'signInToReport': 'Sign in to report a dump.',
    'leaderboard': 'Cleanliness from space',
    'scoreHint': 'Score out of 100, higher is cleaner. Based on active sites, burning, time to clear and verified clean-ups.',
    'recompute': 'Recompute',
    'activeSites': 'Active sites',
    'burnEvents': 'Burn events',
    'daysToClear': 'Median days to clear',
    'verifiedCleared': 'Verified cleared',
    'partActive': 'Few active sites (40)',
    'partBurn': 'Little burning (25)',
    'partClear': 'Quick clean-up (20)',
    'partVerified': 'Verified cleared (15)',
    'askAnything': 'Ask about dumps, wards, fires or scores',
    'assistantHint': 'Answers come only from Drishti data.',
    'anyCity': 'All cities',
    'reports': 'Citizen reports',
    'pipeline': 'Pipeline',
    'users': 'Users',
    'markMatched': 'Link to site',
    'reject': 'Reject',
    'pickSite': 'Link to which site?',
    'queueRun': 'Queue run',
    'detectRun': 'Detect dumps (Sentinel-2)',
    'firesRun': 'Fire layer (NASA FIRMS)',
    'runQueued': "Run queued. Member B's worker will pick it up.",
    'verifyAll': 'Verify all sent complaints',
    'verifiedCount': 'sites checked',
    'role': 'Role',
    'signIn': 'Sign in',
    'signUp': 'Create account',
    'signOut': 'Sign out',
    'email': 'Email',
    'password': 'Password',
    'fullName': 'Full name',
    'noAccount': 'New here? Create an account',
    'haveAccount': 'Have an account? Sign in',
    'language': 'Language',
    'apiMode': 'Connected to the Drishti API (Granite)',
    'localMode': 'Running directly on Supabase (template complaints, built-in assistant)',
    'staffOnly': 'For ward officers and admins',
    'legend': 'Legend',
    'foundLine': 'AI found {n} dumps in {place}. {m} are not on any government record.',
    'status_active': 'Active',
    'status_complaint_sent': 'Complaint sent',
    'status_cleanup_reported': 'Clean-up reported',
    'status_cleared': 'Cleared',
    'status_dismissed': 'Dismissed',
    'status_draft': 'Draft',
    'status_approved': 'Approved',
    'status_sent': 'Sent',
    'status_closed': 'Closed',
    'status_new': 'New',
    'status_matched': 'Matched',
    'status_rejected': 'Rejected',
    'status_queued': 'Queued',
    'status_running': 'Running',
    'status_done': 'Done',
    'status_failed': 'Failed',
    'result_still_present': 'Still present',
    'result_shrinking': 'Shrinking',
    'result_cleared': 'Cleared',
    'role_citizen': 'Citizen',
    'role_officer': 'Ward officer',
    'role_board': 'Pollution control board',
    'role_admin': 'Admin',
  });

  static const hi = S._({
    'appName': 'दृष्टि',
    'tagline': 'भारत का कचरा, अंतरिक्ष से',
    'map': 'नक्शा',
    'scores': 'स्कोर',
    'report': 'रिपोर्ट',
    'assistant': 'सहायक',
    'officials': 'अधिकारी',
    'profile': 'प्रोफ़ाइल',
    'allIndia': 'पूरा भारत',
    'satellite': 'उपग्रह',
    'streets': 'सड़कें',
    'fires': 'आग',
    'wards': 'वार्ड',
    'filters': 'फ़िल्टर',
    'all': 'सभी',
    'nearWater': 'जल के पास',
    'highFireRisk': 'अधिक आग जोखिम',
    'notOnRecord': 'किसी सरकारी रिकॉर्ड में नहीं',
    'onRecord': 'सरकारी रिकॉर्ड में दर्ज',
    'open': 'खोलें',
    'retry': 'फिर कोशिश करें',
    'loading': 'लोड हो रहा है...',
    'somethingWrong': 'कुछ गलत हो गया',
    'nothingHere': 'अभी यहाँ कुछ नहीं है',
    'site': 'स्थल',
    'ward': 'वार्ड',
    'city': 'शहर',
    'area': 'क्षेत्रफल',
    'firstSeen': 'पहली बार देखा',
    'lastSeen': 'अंतिम बार देखा',
    'change': 'बदलाव',
    'fireRisk': 'आग जोखिम',
    'confidence': 'मॉडल विश्वास',
    'location': 'स्थान',
    'openInMaps': 'Google Maps में खोलें',
    'officer': 'वार्ड अधिकारी',
    'timeline': 'समय के साथ बढ़त',
    'timelineHint': 'हर उपग्रह चित्र में स्थल देखने के लिए स्लाइडर खिसकाएँ।',
    'firstSighting': 'पहली बार',
    'sinceFirst': 'पहली बार से',
    'noDetections': 'अभी कोई पहचान नहीं',
    'fireEvents': 'आग के हॉटस्पॉट (NASA FIRMS)',
    'complaints': 'शिकायतें',
    'draftComplaint': 'शिकायत का मसौदा बनाएँ',
    'chooseLanguage': 'शिकायत की भाषा',
    'complaint': 'शिकायत',
    'approve': 'स्वीकृत करें',
    'send': 'वार्ड अधिकारी को भेजें',
    'closeComplaint': 'बंद करें',
    'save': 'सहेजें',
    'saved': 'सहेजा गया',
    'copy': 'पाठ कॉपी करें',
    'copied': 'कॉपी किया गया',
    'openPdf': 'PDF खोलें',
    'emailOpened': 'भेजा गया चिह्नित। आपके ईमेल ऐप में पत्र तैयार है।',
    'verification': 'सफाई जाँच',
    'checkCleanup': 'अभी सफाई जाँचें',
    'changeStatus': 'स्थिति बदलें',
    'statusUpdated': 'स्थिति अपडेट हुई',
    'reportTitle': 'कचरे की रिपोर्ट करें',
    'reportHint': 'नक्शे पर जहाँ कचरा है वहाँ टैप करें, नोट और फ़ोटो जोड़ें।',
    'tapToPlace': 'पिन लगाने के लिए नक्शे पर टैप करें',
    'note': 'नोट',
    'notePlaceholder': 'आपने क्या देखा? जैसे नहर के पास कचरा जल रहा है',
    'addPhoto': 'फ़ोटो जोड़ें',
    'camera': 'कैमरा',
    'gallery': 'गैलरी',
    'submit': 'रिपोर्ट भेजें',
    'reportMatched': 'धन्यवाद! यह पहले से दर्ज एक स्थल से मेल खाता है',
    'reportFlagged': 'धन्यवाद! एक अधिकारी इस नए स्थान की समीक्षा करेंगे।',
    'myReports': 'मेरी रिपोर्टें',
    'signInToReport': 'रिपोर्ट करने के लिए साइन इन करें।',
    'leaderboard': 'अंतरिक्ष से स्वच्छता',
    'scoreHint': '100 में से स्कोर, अधिक यानी अधिक स्वच्छ। सक्रिय स्थल, आग, सफाई में लगा समय और पुष्ट सफाई पर आधारित।',
    'recompute': 'फिर से गणना करें',
    'activeSites': 'सक्रिय स्थल',
    'burnEvents': 'आग की घटनाएँ',
    'daysToClear': 'सफाई में औसत दिन',
    'verifiedCleared': 'पुष्ट सफाई',
    'partActive': 'कम सक्रिय स्थल (40)',
    'partBurn': 'कम आग (25)',
    'partClear': 'जल्दी सफाई (20)',
    'partVerified': 'पुष्ट सफाई (15)',
    'askAnything': 'कचरा स्थल, वार्ड, आग या स्कोर के बारे में पूछें',
    'assistantHint': 'जवाब केवल Drishti डेटा से आते हैं।',
    'anyCity': 'सभी शहर',
    'reports': 'नागरिक रिपोर्टें',
    'pipeline': 'पाइपलाइन',
    'users': 'उपयोगकर्ता',
    'markMatched': 'स्थल से जोड़ें',
    'reject': 'अस्वीकार करें',
    'pickSite': 'किस स्थल से जोड़ें?',
    'queueRun': 'रन कतार में डालें',
    'detectRun': 'कचरा पहचानें (Sentinel-2)',
    'firesRun': 'आग परत (NASA FIRMS)',
    'runQueued': 'रन कतार में है। सदस्य B का वर्कर इसे चलाएगा।',
    'verifyAll': 'सभी भेजी गई शिकायतें जाँचें',
    'verifiedCount': 'स्थल जाँचे गए',
    'role': 'भूमिका',
    'signIn': 'साइन इन',
    'signUp': 'खाता बनाएँ',
    'signOut': 'साइन आउट',
    'email': 'ईमेल',
    'password': 'पासवर्ड',
    'fullName': 'पूरा नाम',
    'noAccount': 'नए हैं? खाता बनाएँ',
    'haveAccount': 'खाता है? साइन इन करें',
    'language': 'भाषा',
    'apiMode': 'Drishti API (Granite) से जुड़ा है',
    'localMode': 'सीधे Supabase पर चल रहा है (टेम्पलेट शिकायत, अंतर्निहित सहायक)',
    'staffOnly': 'वार्ड अधिकारियों और एडमिन के लिए',
    'legend': 'संकेत',
    'foundLine': 'AI ने {place} में {n} कचरा स्थल पाए। {m} किसी सरकारी रिकॉर्ड में नहीं हैं।',
    'status_active': 'सक्रिय',
    'status_complaint_sent': 'शिकायत भेजी गई',
    'status_cleanup_reported': 'सफाई की सूचना',
    'status_cleared': 'साफ़',
    'status_dismissed': 'खारिज',
    'status_draft': 'मसौदा',
    'status_approved': 'स्वीकृत',
    'status_sent': 'भेजी गई',
    'status_closed': 'बंद',
    'status_new': 'नई',
    'status_matched': 'मेल खाई',
    'status_rejected': 'अस्वीकृत',
    'status_queued': 'कतार में',
    'status_running': 'चल रहा है',
    'status_done': 'पूरा',
    'status_failed': 'विफल',
    'result_still_present': 'अभी भी मौजूद',
    'result_shrinking': 'घट रहा है',
    'result_cleared': 'साफ़',
    'role_citizen': 'नागरिक',
    'role_officer': 'वार्ड अधिकारी',
    'role_board': 'प्रदूषण नियंत्रण बोर्ड',
    'role_admin': 'एडमिन',
  });
}
