import 'package:intl/intl.dart';

import '../models/place.dart';
import '../models/site.dart';

/// Template complaint used when Member C's Granite API is not running.
/// Like the Granite drafter it states what the imagery shows and asks for an
/// inspection; it never accuses anyone.
class ComplaintDrafter {
  static const languages = ['English', 'Hindi'];

  static String draft(Site site, {City? city, required String language, DateTime? today}) {
    final date = DateFormat('d MMM yyyy').format(today ?? DateTime.now());
    final cityName = city?.name ?? site.cityId;
    final ward = site.wardNo != null ? '${site.wardNo} (${site.wardName ?? '-'})' : (site.wardName ?? '-');
    final area = site.areaM2.round();
    final first = site.firstSeen == null ? '-' : DateFormat('d MMM yyyy').format(site.firstSeen!);
    final last = site.lastSeen == null ? '-' : DateFormat('d MMM yyyy').format(site.lastSeen!);
    final coords = site.point == null
        ? '-'
        : '${site.lat!.toStringAsFixed(5)}, ${site.lng!.toStringAsFixed(5)}';
    final mapLink = site.point == null ? '' : 'https://www.google.com/maps?q=${site.lat},${site.lng}';
    final conf = site.confidence == null ? null : (site.confidence! * 100).round();

    if (language == 'Hindi') {
      return [
        'दिनांक: $date',
        'सेवा में: वार्ड अधिकारी, वार्ड $ward, $cityName',
        'विषय: संदिग्ध अवैध कचरा स्थल का निरीक्षण करने का अनुरोध (साइट ${site.id})',
        '',
        'महोदय/महोदया,',
        '',
        'Sentinel-2 उपग्रह चित्रों के विश्लेषण से आपके वार्ड में एक संदिग्ध कचरा स्थल दिखाई देता है:',
        '- स्थान: $coords $mapLink',
        '- अनुमानित क्षेत्रफल: $area वर्ग मीटर',
        '- पहली बार देखा गया: $first, अंतिम बार देखा गया: $last',
        if (site.growth != null) '- बदलाव: ${site.growth}',
        if (site.nearWater) '- यह स्थल किसी जल स्रोत के पास है, जिससे जल प्रदूषण का खतरा है।',
        if (site.highFireRisk) '- आग का जोखिम अधिक है (स्कोर ${site.fireRisk}/100)।',
        if (conf != null) '- मॉडल का विश्वास स्तर: $conf%',
        '',
        'ठोस अपशिष्ट प्रबंधन नियम, 2026 (1 अप्रैल 2026 से लागू) के अंतर्गत, कृपया इस स्थल का निरीक्षण कराएँ और यदि कचरा पाया जाए तो उसे हटवाने की व्यवस्था करें। '
            'Drishti आने वाले उपग्रह चित्रों में इस स्थल की सफाई की पुष्टि करेगा।',
        '',
        'यह सूचना स्वचालित उपग्रह विश्लेषण पर आधारित है और किसी व्यक्ति या संस्था पर आरोप नहीं है।',
        '',
        'धन्यवाद,',
        'Project Drishti',
      ].join('\n');
    }

    return [
      'Date: $date',
      'To: Ward Officer, Ward $ward, $cityName',
      'Subject: Request to inspect a suspected illegal dumpsite (site ${site.id})',
      '',
      'Dear Sir/Madam,',
      '',
      'Analysis of Sentinel-2 satellite imagery indicates a suspected waste dumpsite in your ward:',
      '- Location: $coords $mapLink',
      '- Estimated area: $area m2',
      '- First seen: $first, last seen: $last',
      if (site.growth != null) '- Change: ${site.growth}',
      if (site.nearWater) '- The site is close to a water body, so there is a risk of water pollution.',
      if (site.highFireRisk) '- Fire risk is high (score ${site.fireRisk}/100).',
      if (conf != null) '- Model confidence: $conf%',
      '',
      'Under the Solid Waste Management Rules, 2026 (in force from 1 April 2026), we request that the site be inspected and, '
          'if waste is found, cleared. Drishti will check the clean-up in the next satellite passes.',
      '',
      'This notice is based on automated satellite analysis and does not accuse any person or organisation.',
      '',
      'Regards,',
      'Project Drishti',
    ].join('\n');
  }
}
