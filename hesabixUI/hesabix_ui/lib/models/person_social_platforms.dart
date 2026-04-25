/// کلیدهای `platform_key` هم‌نام با API
const List<String> kPersonSocialPlatformKeys = [
  'telegram',
  'bale',
  'rubika',
  'eitaa',
  'whatsapp',
  'instagram',
  'linkedin',
  'twitter',
  'other',
];

const Map<String, String> kPersonSocialPlatformLabelsFa = {
  'telegram': 'تلگرام',
  'bale': 'بله',
  'rubika': 'روبیکا',
  'eitaa': 'ایتا',
  'whatsapp': 'واتساپ',
  'instagram': 'اینستاگرام',
  'linkedin': 'لینکدین',
  'twitter': 'توییتر / X',
  'other': 'سایر',
};

String personSocialPlatformLabelFa(String platformKey, {String? customLabel}) {
  if (platformKey == 'other' && customLabel != null && customLabel.trim().isNotEmpty) {
    return customLabel.trim();
  }
  return kPersonSocialPlatformLabelsFa[platformKey] ?? platformKey;
}
