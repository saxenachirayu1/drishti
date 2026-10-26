import '../services/tracking_logic.dart';

/// Text for the design D screens (home, raise, track, department console,
/// impact) in English and Hindi. The older screens keep using the ARB files.
class DS {
  const DS(this.hindi);
  final bool hindi;

  String _(String en, String hi) => hindi ? hi : en;

  // --- home --------------------------------------------------------------------
  String get navMap => _('Map', 'नक्शा');
  String get navTrack => _('Track a complaint', 'शिकायत देखें');
  String get navOfficials => _('Officials', 'अधिकारी');
  String get navImpact => _('Impact', 'असर');
  String get h1 => _('Your city, seen from space every five days.', 'आपका शहर, हर पाँच दिन में अंतरिक्ष से।');
  String get sub => _(
    'Drishti spots open dumps and burning, tells the people who can fix them, and shows you when the ground is clean again.',
    'दृष्टि खुले कचरे और जलते ढेर पहचानती है, ज़िम्मेदार विभाग को बताती है, और ज़मीन साफ़ होने पर आपको दिखाती है।',
  );
  String get searchLabel => _('Check your area', 'अपना इलाका देखें');
  String get searchHint => _('Area or PIN code', 'इलाका या पिन कोड');
  String get searchBtn => _('Look', 'देखें');
  String get searchEmptyTitle => _('Type an area first', 'कोई इलाका लिखें');
  String get searchEmptyBody => _('For example Shivajinagar, Kothrud or 411005', 'जैसे शिवाजीनगर, कोथरुड या 411005');
  String get searchMissTitle => _('We do not cover this area yet', 'यह इलाका अभी शामिल नहीं');
  String get searchMissBody =>
      _('Pune, Delhi, Indore and Bhopal are live today.', 'अभी पुणे, दिल्ली, इंदौर और भोपाल शामिल हैं।');
  String get searchFailed =>
      _('Could not search right now. Check the connection.', 'अभी खोज नहीं हो सकी। इंटरनेट देखें।');
  String openRecords(int n) => n == 0
      ? _('No open records within 3 km.', '3 किमी में कोई खुला रिकॉर्ड नहीं।')
      : _('$n open record${n == 1 ? '' : 's'} within 3 km.', '3 किमी में $n खुले रिकॉर्ड।');
  String lastPass(String date) => _('Last pass $date.', 'आख़िरी तस्वीर $date।');
  String get seeOnMap => _('See it on the map', 'नक्शे पर देखें');
  String get raise => _('Raise a complaint', 'शिकायत दर्ज करें');
  String get openMap => _('Open the map', 'नक्शा खोलें');
  String get trackYours => _('Track your complaint', 'अपनी शिकायत देखें');
  String get sliderLabel =>
      _('Drag to compare the two satellite passes', 'दोनों सैटेलाइट तस्वीरों की तुलना के लिए खींचें');
  String get caption => _(
    'Illustration of a site. Drag to compare two passes six weeks apart.',
    'एक जगह का चित्र। छह हफ़्ते के अंतर वाली दो तस्वीरें, खींचकर तुलना करें।',
  );
  String get clean => _('CLEAN', 'साफ़');
  String get journeyH => _('From a pixel to a clean street', 'एक पिक्सेल से साफ़ गली तक');
  List<String> get journeyNames =>
      hindi ? const ['दिखा', 'बताया', 'काम', 'साबित'] : const ['Seen', 'Told', 'Fixed', 'Proven'];
  List<String> get journeyText => hindi
      ? const [
          'सैटेलाइट लगभग हर पाँच दिन शहर की तस्वीर लेता है, और मॉडल लगभग 30 मीटर से बड़े हर ढेर को घेर देता है।',
          'सही विभाग को जगह, तस्वीरें और हिंदी या अंग्रेज़ी में तैयार शिकायत मिलती है। भेजने से पहले अधिकारी उसे जाँचते हैं।',
          'टीम काम करते हुए अपडेट डालती है, और आप हर अपडेट तुरंत देखते हैं, जगह की फ़ोटो के साथ।',
          'जगह तभी साफ़ मानी जाती है जब अगली दो सैटेलाइट तस्वीरों में वहाँ कुछ न दिखे। वादा सबूत नहीं है।',
        ]
      : const [
          'A satellite photographs the city about every five days, and the model outlines every dump bigger than about 30 metres across.',
          'The right department gets the site, the photos and a drafted complaint in Hindi or English. An officer reviews it before it goes out.',
          'The team posts updates as they work, and you see each one live, with photos from the site.',
          'It only counts as clean when two later satellite passes show nothing there. A promise is not proof.',
        ];
  static const journeyTags = ['SENTINEL-2 · IBM PRITHVI', 'IBM GRANITE', 'MUNICIPAL SWM · PWD', 'NEXT TWO PASSES'];
  String get goal => _(
    'India aims to clear every legacy dumpsite by September 2026.',
    'भारत का लक्ष्य: सितंबर 2026 तक हर पुराना कचरा-स्थल साफ़।',
  );
  String get goalBarLabel =>
      _('1,048 of 2,476 legacy dumpsites fully cleared', '2,476 में से 1,048 पुराने कचरा-स्थल पूरी तरह साफ़');
  String get goalNote => _(
    'legacy dumpsites fully cleared so far. Drishti helps by catching new ones before they grow.',
    'पुराने कचरा-स्थल अब तक पूरी तरह साफ़। दृष्टि नए ढेरों को बढ़ने से पहले पकड़ती है।',
  );
  String get goalSource => _(
    'Swachh Bharat Mission (Urban) 2.0 figures, Ministry of Housing and Urban Affairs via PIB, November 2025',
    'स्वच्छ भारत मिशन (शहरी) 2.0, आवास और शहरी कार्य मंत्रालय, PIB, नवंबर 2025',
  );
  String get followH => _('Come back when your street changes', 'जब आपकी गली में कुछ बदले, तब लौटें');
  String get followBody => _(
    'Follow an area and see when a new dump appears, when a complaint moves, and when a satellite pass proves it clean.',
    'किसी इलाके को फ़ॉलो करें। नया ढेर दिखे, शिकायत आगे बढ़े, या सैटेलाइट सफ़ाई की पुष्टि करे, आप देख पाएँगे।',
  );
  String get followFind => _('Find your area first', 'पहले अपना इलाका खोजें');
  String follow(String area) => _('Follow $area', '$area फ़ॉलो करें');
  String following(String area) => _('Following $area ✓', '$area फ़ॉलो हो रहा है ✓');
  String get followSignIn => _('Sign in to follow an area.', 'इलाका फ़ॉलो करने के लिए साइन इन करें।');
  String nextPass(String city, String date) =>
      _('NEXT PASS OVER ${city.toUpperCase()} · AROUND $date', '$city के ऊपर अगली तस्वीर · लगभग $date');
  String get revisit => _('SENTINEL-2 REVISITS EVERY FIVE DAYS', 'सेंटिनल-2 हर पाँच दिन लौटता है');
  String get closing =>
      _('Seen something the satellite missed? Your photo counts.', 'सैटेलाइट से कुछ छूट गया? आपकी फ़ोटो भी सबूत है।');
  String get privacy => _('Privacy', 'गोपनीयता');
  String get about => _('About', 'परिचय');
  String get privacyBody => _(
    'Your photo is re-saved without its location data before upload, and only you and the officers can open it. '
        'Anyone with a ticket code sees where a complaint went and what the department said, never who raised it or your note. '
        'We keep your email to sign you in and nothing else.',
    'अपलोड से पहले आपकी फ़ोटो से लोकेशन डेटा हटा दिया जाता है, और उसे सिर्फ़ आप और अधिकारी खोल सकते हैं। '
        'टिकट कोड से कोई भी देख सकता है कि शिकायत कहाँ गई और विभाग ने क्या कहा, पर यह नहीं कि किसने की या आपका नोट। '
        'आपका ईमेल सिर्फ़ साइन इन के लिए रखा जाता है।',
  );
  String get aboutBody => _(
    'Drishti reads free Copernicus Sentinel-2 imagery with IBM Prithvi-EO-2.0 to find open dumps, checks NASA FIRMS for fires, '
        'and drafts complaints with IBM Granite. It is a hackathon project for the IBM SkillsBuild programme; '
        'reply targets are placeholders until a ward office confirms them.',
    'दृष्टि मुफ़्त कोपरनिकस सेंटिनल-2 तस्वीरों को IBM Prithvi-EO-2.0 से पढ़कर खुले कचरे के ढेर खोजती है, NASA FIRMS से आग देखती है, '
        'और IBM Granite से शिकायत तैयार करती है। यह IBM SkillsBuild हैकाथॉन प्रोजेक्ट है; '
        'जवाब के लक्ष्य समय तब तक अनुमान हैं जब तक कोई वार्ड कार्यालय पुष्टि न करे।',
  );
  String get close => _('Close', 'बंद करें');
  static const credits =
      'Copernicus Sentinel-2 (ESA) · NASA FIRMS · IBM Prithvi-EO-2.0 and IBM Granite · © OpenStreetMap contributors';

  // --- complaint types and departments ----------------------------------------
  String typeName(String id) => switch (id) {
    'dump' => _('Garbage dump', 'कचरे का ढेर'),
    'burning' => _('Waste burning', 'कचरा जलाना'),
    'bin' => _('Bin or pickup', 'कूड़ेदान या उठान'),
    'debris' => _('Construction debris', 'निर्माण का मलबा'),
    _ => id,
  };
  String typeHint(String id) => switch (id) {
    'dump' => _('heap or open dumping', 'ढेर या खुले में फेंका कचरा'),
    'burning' => _('smoke or fire now', 'अभी धुआँ या आग'),
    'bin' => _('overflowing, missed', 'भरा हुआ, उठान छूटी'),
    'debris' => _('rubble on a road', 'सड़क पर मलबा'),
    _ => '',
  };
  String deptName(String? id) => switch (id) {
    'swm' => _('Municipal SWM office', 'नगर निगम ठोस अपशिष्ट कार्यालय'),
    'pwd' => _('PWD road division', 'लोक निर्माण विभाग, सड़क खंड'),
    'cnd' => _('Municipal C&D waste cell', 'नगर निगम मलबा प्रकोष्ठ'),
    _ => _('The city', 'नगर निगम'),
  };
  String deptWhy(String type, {required bool onPwdRoad}) => switch (type) {
    'burning' => _(
      'Burning goes to the top of the officer\'s list and is cross-checked with NASA FIRMS.',
      'कचरा जलाना अधिकारी की सूची में सबसे ऊपर जाता है और NASA FIRMS से मिलाया जाता है।',
    ),
    'bin' => _(
      'Collection and bins are run by the ward\'s SWM team.',
      'कचरा उठान और कूड़ेदान वार्ड की SWM टीम देखती है।',
    ),
    'debris' when onPwdRoad => _(
      'This spot is on a PWD road, so the debris goes to PWD.',
      'यह जगह लोक निर्माण विभाग की सड़क पर है, इसलिए मलबा PWD को जाता है।',
    ),
    'debris' => _(
      'Debris on a city road goes to the municipal C&D waste cell. On a PWD road it would go to PWD.',
      'शहर की सड़क पर मलबा नगर निगम के मलबा प्रकोष्ठ को जाता है। PWD सड़क पर होता तो PWD को जाता।',
    ),
    _ => _(
      'Open dumping is handled by the municipal Solid Waste Management department.',
      'खुले में कचरा फेंकना नगर निगम का ठोस अपशिष्ट प्रबंधन विभाग देखता है।',
    ),
  };
  String ward(int? no, String? name) => no == null
      ? _('Outside our mapped wards', 'हमारे वार्ड नक्शे से बाहर')
      : _('Ward $no', 'वार्ड $no') + (name == null ? '' : ' · $name');
  String replyTarget(int hours) => _('FIRST REPLY TARGET · $hours H', 'पहले जवाब का लक्ष्य · $hours घंटे');

  // --- raise --------------------------------------------------------------------
  String get raiseTitle => _('Raise a complaint', 'शिकायत दर्ज करें');
  String get step1 => _('1 · What\'s wrong?', '1 · क्या समस्या है?');
  String get step2 => _('2 · Where', '2 · कहाँ');
  String get step3 => _('3 · A photo and a note', '3 · फ़ोटो और नोट');
  String get tapMap => _('Tap the map where it is, or use your location.', 'नक्शे पर जगह छुएँ, या अपनी लोकेशन लें।');
  String get useLocation => _('Use my location', 'मेरी लोकेशन');
  String get locating => _('Finding you…', 'ढूँढ रहे हैं…');
  String get noLocation =>
      _('Could not get your location. Tap the map instead.', 'लोकेशन नहीं मिली। नक्शे पर जगह छुएँ।');
  String get addPhoto => _('Add photo', 'फ़ोटो जोड़ें');
  String get camera => _('Camera', 'कैमरा');
  String get gallery => _('Gallery', 'गैलरी');
  String get removePhoto => _('Remove photo', 'फ़ोटो हटाएँ');
  String get photoPrivate => _(
    'Location data is removed from the photo before upload.',
    'अपलोड से पहले फ़ोटो से लोकेशन डेटा हटा दिया जाता है।',
  );
  String get noteLabel => _('Anything the team should know (optional)', 'टीम के लिए कुछ और (वैकल्पिक)');
  String get noteHint =>
      _('e.g. Behind the bus stop, burning since morning', 'जैसे बस स्टॉप के पीछे, सुबह से जल रहा है');
  String get goesTo => _('GOES TO', 'किसे जाएगी');
  String get pickPlaceFirst => _('Mark the place on the map first.', 'पहले नक्शे पर जगह बताएँ।');
  String get send => _('Raise complaint', 'शिकायत भेजें');
  String get sending => _('Sending…', 'भेज रहे हैं…');
  String get signInToRaise => _(
    'Sign in to raise a complaint. We email you a code; no password needed.',
    'शिकायत दर्ज करने के लिए साइन इन करें। हम ईमेल पर कोड भेजेंगे, पासवर्ड नहीं चाहिए।',
  );
  String get sentTitle => _('Complaint raised', 'शिकायत दर्ज हुई');
  String sentBody(String ticket, String dept) => _(
    '$ticket went to the $dept. Keep the code to follow it from any phone.',
    '$ticket $dept को गई। किसी भी फ़ोन से देखने के लिए यह कोड रखें।',
  );
  String sentMatched(String site) => _(
    'It matches satellite record $site, so the officer sees both together.',
    'यह सैटेलाइट रिकॉर्ड $site से मिलती है, इसलिए अधिकारी दोनों साथ देखेंगे।',
  );
  String get followIt => _('Follow it live', 'लाइव देखें');
  String get done => _('Done', 'ठीक है');

  // --- track --------------------------------------------------------------------
  String get trackTitle => _('Track a complaint', 'शिकायत देखें');
  String get ticketLabel => _('Ticket code', 'टिकट कोड');
  String get ticketHint => _('e.g. DRI-Q-0412', 'जैसे DRI-Q-0412');
  String get ticketBad => _(
    'That does not look like a ticket code. It reads like DRI-Q-0412.',
    'यह टिकट कोड जैसा नहीं लगता। कोड ऐसा होता है: DRI-Q-0412',
  );
  String get ticketMissing => _('No complaint with that code.', 'इस कोड की कोई शिकायत नहीं।');
  String get yourComplaints => _('Your complaints', 'आपकी शिकायतें');
  String get noComplaints => _(
    'Nothing raised yet. When you raise one, it appears here and updates live.',
    'अभी कोई शिकायत नहीं। दर्ज करने पर यहाँ दिखेगी और अपने-आप अपडेट होगी।',
  );
  String get live => _('LIVE', 'लाइव');
  String get liveHint => _('Updates appear here as the department posts them.', 'विभाग के अपडेट यहाँ अपने-आप आते हैं।');
  String headline(String stage) => switch (stage) {
    'received' => _('Received', 'मिल गई'),
    'assigned' => _('Assigned to an officer', 'अधिकारी को सौंपी गई'),
    'scheduled' => _('Work is scheduled', 'काम तय हुआ'),
    'in_progress' => _('Work has started', 'काम शुरू हुआ'),
    'resolved' => _('Marked resolved', 'हल बताई गई'),
    'proven_clean' => _('Proven clean from space', 'अंतरिक्ष से साफ़ साबित'),
    'reopened' => _('Reopened', 'फिर से खोली गई'),
    _ => stage,
  };
  String stamp(String stage) => switch (stage) {
    'received' => _('RECEIVED', 'मिली'),
    'assigned' => _('ASSIGNED', 'सौंपी'),
    'scheduled' => _('SCHEDULED', 'तय'),
    'in_progress' => _('WORK STARTED', 'काम शुरू'),
    'resolved' => _('RESOLVED', 'हल'),
    'proven_clean' => _('PROVEN CLEAN', 'साफ़ साबित'),
    'reopened' => _('REOPENED', 'फिर खुली'),
    'note' => _('UPDATE', 'अपडेट'),
    _ => stage.toUpperCase(),
  };
  String get nextProof => _('NEXT · PROVEN CLEAN FROM SPACE', 'आगे · अंतरिक्ष से साफ़ साबित');
  String get nextProofBody => _(
    'Checked on the next two satellite passes after the team marks it resolved.',
    'टीम के हल बताने के बाद अगली दो सैटेलाइट तस्वीरों में जाँच होगी।',
  );
  String clockText(ReplyClock c, int targetHours) => switch (c) {
    Replied(:final took, :final onTime) =>
      onTime
          ? _(
              'First reply in ${shortDuration(took)} ✓ (target $targetHours h)',
              'पहला जवाब ${shortDuration(took, hindi: true)} में ✓ (लक्ष्य $targetHours घंटे)',
            )
          : _(
              'First reply in ${shortDuration(took)}, late (target $targetHours h)',
              'पहला जवाब ${shortDuration(took, hindi: true)} में, देर से (लक्ष्य $targetHours घंटे)',
            ),
    DueIn(:final left) => _(
      'Reply due in ${shortDuration(left)}',
      'जवाब ${shortDuration(left, hindi: true)} में अपेक्षित',
    ),
    Overdue(:final by) => _(
      'No reply yet · ${shortDuration(by)} past the target',
      'अभी जवाब नहीं · लक्ष्य से ${shortDuration(by, hindi: true)} ऊपर',
    ),
    NoClock() => '',
  };
  String get reopen => _('Not fixed? Reopen', 'ठीक नहीं हुआ? फिर खोलें');
  String get reopenTitle => _('What is still wrong?', 'अब भी क्या गड़बड़ है?');
  String get reopenHint => _('e.g. The heap is back by the wall', 'जैसे दीवार के पास ढेर फिर लग गया');
  String get reopenSend => _('Reopen', 'फिर खोलें');
  String get reopened => _('Reopened. The department has been told.', 'फिर खोली गई। विभाग को बता दिया गया।');
  String get cancel => _('Cancel', 'रद्द करें');
  String get copyCode => _('Copy code', 'कोड कॉपी करें');
  String get copied => _('Code copied', 'कोड कॉपी हुआ');
  String get bySystem => _('Drishti', 'दृष्टि');
  String get byDept => _('Department', 'विभाग');
  String get byYou => _('You', 'आप');
  String get photoAttached => _('Photo from the site', 'जगह की फ़ोटो');
  String get signInForPhotos => _(
    'Sign in as the person who raised it to see photos.',
    'फ़ोटो देखने के लिए शिकायतकर्ता के रूप में साइन इन करें।',
  );

  // --- department console -----------------------------------------------------------
  String get consoleTitle => _('Complaints', 'शिकायतें');
  String get allDepts => _('All departments', 'सभी विभाग');
  String get filterOpen => _('Open', 'खुली');
  String get filterOverdue => _('Overdue', 'देर');
  String get filterBurning => _('Burning', 'आग');
  String get filterClosed => _('Closed', 'बंद');
  String nOverdue(int n) => _('$n overdue', '$n देर से');
  String nOpen(int n) => _('$n open', '$n खुली');
  String onTimeMonth(int? pct) =>
      pct == null ? _('No replies yet', 'अभी कोई जवाब नहीं') : _('$pct% replied on time', '$pct% समय पर जवाब');
  String get pickOne => _('Pick a complaint from the list.', 'सूची से कोई शिकायत चुनें।');
  String get queueEmpty => _('Nothing here. Good.', 'यहाँ कुछ नहीं।');
  String get postUpdate => _('Post an update', 'अपडेट डालें');
  String get newStage => _('New status', 'नई स्थिति');
  String get justNote => _('Message only', 'सिर्फ़ संदेश');
  String get messageLabel =>
      _('Message to the resident (English or Hindi)', 'शिकायतकर्ता को संदेश (हिंदी या अंग्रेज़ी)');
  String get attachAfter => _('Attach after photo (required to resolve)', 'बाद की फ़ोटो जोड़ें (हल के लिए ज़रूरी)');
  String get afterAttached => _('After photo attached', 'बाद की फ़ोटो जुड़ी');
  String get residentSees => _('The resident sees this instantly.', 'शिकायतकर्ता इसे तुरंत देखते हैं।');
  String get post => _('Post update', 'अपडेट डालें');
  String get posted => _('Update posted', 'अपडेट डाला गया');
  String get resolveNote => _(
    'Marking it resolved queues a satellite check. It becomes proven clean only when the record clears.',
    'हल बताने पर सैटेलाइट जाँच कतार में जाती है। रिकॉर्ड साफ़ होने पर ही यह साफ़ साबित होती है।',
  );
  String get needPhoto => _('Attach an after photo to resolve.', 'हल के लिए बाद की फ़ोटो जोड़ें।');
  String get needMessage => _('Write a message.', 'संदेश लिखें।');
  String transferTo(String dept) => _('Transfer to $dept', '$dept को भेजें');
  String get transferred => _('Transferred', 'भेजी गई');
  String get raisedBy => _('Raised by a resident', 'एक नागरिक ने दर्ज की');
  String linkedTo(String site) => _('linked to satellite record $site', 'सैटेलाइट रिकॉर्ड $site से जुड़ी');
  String get residentPhoto => _('Resident\'s photo', 'नागरिक की फ़ोटो');
  String get noPhoto => _('No photo', 'फ़ोटो नहीं');
  String get openSite => _('Open the satellite record', 'सैटेलाइट रिकॉर्ड खोलें');
  String get staffOnly => _(
    'This console is for ward officers and departments. Ask an admin for access.',
    'यह वार्ड अधिकारियों और विभागों के लिए है। पहुँच के लिए एडमिन से कहें।',
  );
  String get back => _('Back', 'वापस');

  // --- impact -----------------------------------------------------------------------------
  String get impactTitle => _('Impact', 'असर');
  String get impactSub =>
      _('Counted live from the records. Nothing here is estimated.', 'रिकॉर्ड से सीधे गिना गया। कुछ भी अनुमान नहीं।');
  String get allCities => _('All cities', 'सभी शहर');
  String get kSitesFound => _('Sites found from space', 'अंतरिक्ष से मिली जगहें');
  String get kOpen => _('Still open', 'अब भी खुली');
  String get kProven => _('Cleared', 'साफ़ हुई');
  String get kArea => _('Open dump area', 'खुले ढेर का क्षेत्र');
  String get kComplaints => _('Complaints raised', 'दर्ज शिकायतें');
  String get kResolved => _('Resolved', 'हल');
  String get kProvenComplaints => _('Proven clean', 'साफ़ साबित');
  String get kOnTime => _('First reply on time', 'समय पर पहला जवाब');
  String get kMedian => _('Typical first reply', 'आम तौर पर पहला जवाब');
  String get kFires => _('Fires seen, last 30 days', 'पिछले 30 दिन में आग');
  String get byType => _('Complaints by type', 'प्रकार के अनुसार शिकायतें');
  String get funnel => _('From found to proven', 'मिलने से साबित होने तक');
  String get none => _('None yet', 'अभी नहीं');
  String get cityScores => _('City cleanliness scores', 'शहरों के स्वच्छता अंक');
  String get nationalH => _('Where India stands', 'भारत कहाँ है');
}
