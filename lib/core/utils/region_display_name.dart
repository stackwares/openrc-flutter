// English display names for ISO 3166-1 alpha-2 codes.
// Data source: ISO-3166-Countries-with-Regional-Codes (lukes).
//
// All UI-facing labels cap at two words; formal ISO names use the segment before
// the first comma when present (e.g. "Bolivia, Plurinational State of" → "Bolivia").

/// Prefer the primary segment before a comma for formal ISO names.
String _formalCountryDisplayBase(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return t;
  final comma = t.indexOf(',');
  if (comma >= 3) {
    final head = t.substring(0, comma).trim();
    if (head.isNotEmpty) return head;
  }
  return t;
}

String _regionNameAtMostTwoWords(String name) {
  final t = name.trim();
  if (t.isEmpty) return t;
  final parts = t.split(RegExp(r'\s+'));
  if (parts.isEmpty) return t;
  String clean(String w) => w.replaceAll(RegExp(r',\s*$'), '');
  if (parts.length <= 2) {
    return parts.map(clean).join(' ');
  }
  return '${clean(parts[0])} ${clean(parts[1])}';
}

/// ISO alpha-2 codes, or free-form country strings from APIs, resolved to a short
/// English label (at most two words) for display.
String regionDisplayNameEnglish(String? alpha2Code) {
  if (alpha2Code == null || alpha2Code.isEmpty) return '';
  final trimmed = alpha2Code.trim();
  final isAlpha2 =
      trimmed.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(trimmed);
  if (isAlpha2) {
    final key = trimmed.toUpperCase();
    final raw = _kIso3166Alpha2English[key] ?? key;
    return _regionNameAtMostTwoWords(_formalCountryDisplayBase(raw));
  }
  return _regionNameAtMostTwoWords(_formalCountryDisplayBase(trimmed));
}

/// Alias for call sites that previously used a shorter badge variant; behavior
/// matches [regionDisplayNameEnglish].
String regionDisplayNameForCompactBadge(String? alpha2Code) {
  return regionDisplayNameEnglish(alpha2Code);
}

const Map<String, String> _kIso3166Alpha2English = {
  'AD': 'Andorra',
  'AE': 'United Arab Emirates',
  'AF': 'Afghanistan',
  'AG': 'Antigua and Barbuda',
  'AI': 'Anguilla',
  'AL': 'Albania',
  'AM': 'Armenia',
  'AO': 'Angola',
  'AQ': 'Antarctica',
  'AR': 'Argentina',
  'AS': 'American Samoa',
  'AT': 'Austria',
  'AU': 'Australia',
  'AW': 'Aruba',
  'AX': 'Åland Islands',
  'AZ': 'Azerbaijan',
  'BA': 'Bosnia and Herzegovina',
  'BB': 'Barbados',
  'BD': 'Bangladesh',
  'BE': 'Belgium',
  'BF': 'Burkina Faso',
  'BG': 'Bulgaria',
  'BH': 'Bahrain',
  'BI': 'Burundi',
  'BJ': 'Benin',
  'BL': 'Saint Barthélemy',
  'BM': 'Bermuda',
  'BN': 'Brunei Darussalam',
  'BO': 'Bolivia, Plurinational State of',
  'BQ': 'Bonaire, Sint Eustatius and Saba',
  'BR': 'Brazil',
  'BS': 'Bahamas',
  'BT': 'Bhutan',
  'BV': 'Bouvet Island',
  'BW': 'Botswana',
  'BY': 'Belarus',
  'BZ': 'Belize',
  'CA': 'Canada',
  'CC': 'Cocos (Keeling) Islands',
  'CD': 'Congo, Democratic Republic of the',
  'CF': 'Central African Republic',
  'CG': 'Congo',
  'CH': 'Switzerland',
  'CI': 'Côte d\'Ivoire',
  'CK': 'Cook Islands',
  'CL': 'Chile',
  'CM': 'Cameroon',
  'CN': 'China',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'CU': 'Cuba',
  'CV': 'Cabo Verde',
  'CW': 'Curaçao',
  'CX': 'Christmas Island',
  'CY': 'Cyprus',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DJ': 'Djibouti',
  'DK': 'Denmark',
  'DM': 'Dominica',
  'DO': 'Dominican Republic',
  'DZ': 'Algeria',
  'EC': 'Ecuador',
  'EE': 'Estonia',
  'EG': 'Egypt',
  'EH': 'Western Sahara',
  'ER': 'Eritrea',
  'ES': 'Spain',
  'ET': 'Ethiopia',
  'FI': 'Finland',
  'FJ': 'Fiji',
  'FK': 'Falkland Islands (Malvinas)',
  'FM': 'Micronesia, Federated States of',
  'FO': 'Faroe Islands',
  'FR': 'France',
  'GA': 'Gabon',
  'GB': 'United Kingdom of Great Britain and Northern Ireland',
  'GD': 'Grenada',
  'GE': 'Georgia',
  'GF': 'French Guiana',
  'GG': 'Guernsey',
  'GH': 'Ghana',
  'GI': 'Gibraltar',
  'GL': 'Greenland',
  'GM': 'Gambia',
  'GN': 'Guinea',
  'GP': 'Guadeloupe',
  'GQ': 'Equatorial Guinea',
  'GR': 'Greece',
  'GS': 'South Georgia and the South Sandwich Islands',
  'GT': 'Guatemala',
  'GU': 'Guam',
  'GW': 'Guinea-Bissau',
  'GY': 'Guyana',
  'HK': 'Hong Kong',
  'HM': 'Heard Island and McDonald Islands',
  'HN': 'Honduras',
  'HR': 'Croatia',
  'HT': 'Haiti',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IM': 'Isle of Man',
  'IN': 'India',
  'IO': 'British Indian Ocean Territory',
  'IQ': 'Iraq',
  'IR': 'Iran, Islamic Republic of',
  'IS': 'Iceland',
  'IT': 'Italy',
  'JE': 'Jersey',
  'JM': 'Jamaica',
  'JO': 'Jordan',
  'JP': 'Japan',
  'KE': 'Kenya',
  'KG': 'Kyrgyzstan',
  'KH': 'Cambodia',
  'KI': 'Kiribati',
  'KM': 'Comoros',
  'KN': 'Saint Kitts and Nevis',
  'KP': 'Korea, Democratic People\'s Republic of',
  'KR': 'Korea, Republic of',
  'KW': 'Kuwait',
  'KY': 'Cayman Islands',
  'KZ': 'Kazakhstan',
  'LA': 'Lao People\'s Democratic Republic',
  'LB': 'Lebanon',
  'LC': 'Saint Lucia',
  'LI': 'Liechtenstein',
  'LK': 'Sri Lanka',
  'LR': 'Liberia',
  'LS': 'Lesotho',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'LV': 'Latvia',
  'LY': 'Libya',
  'MA': 'Morocco',
  'MC': 'Monaco',
  'MD': 'Moldova, Republic of',
  'ME': 'Montenegro',
  'MF': 'Saint Martin (French part)',
  'MG': 'Madagascar',
  'MH': 'Marshall Islands',
  'MK': 'North Macedonia',
  'ML': 'Mali',
  'MM': 'Myanmar',
  'MN': 'Mongolia',
  'MO': 'Macao',
  'MP': 'Northern Mariana Islands',
  'MQ': 'Martinique',
  'MR': 'Mauritania',
  'MS': 'Montserrat',
  'MT': 'Malta',
  'MU': 'Mauritius',
  'MV': 'Maldives',
  'MW': 'Malawi',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'MZ': 'Mozambique',
  'NA': 'Namibia',
  'NC': 'New Caledonia',
  'NE': 'Niger',
  'NF': 'Norfolk Island',
  'NG': 'Nigeria',
  'NI': 'Nicaragua',
  'NL': 'Netherlands, Kingdom of the',
  'NO': 'Norway',
  'NP': 'Nepal',
  'NR': 'Nauru',
  'NU': 'Niue',
  'NZ': 'New Zealand',
  'OM': 'Oman',
  'PA': 'Panama',
  'PE': 'Peru',
  'PF': 'French Polynesia',
  'PG': 'Papua New Guinea',
  'PH': 'Philippines',
  'PK': 'Pakistan',
  'PL': 'Poland',
  'PM': 'Saint Pierre and Miquelon',
  'PN': 'Pitcairn',
  'PR': 'Puerto Rico',
  'PS': 'Palestine, State of',
  'PT': 'Portugal',
  'PW': 'Palau',
  'PY': 'Paraguay',
  'QA': 'Qatar',
  'RE': 'Réunion',
  'RO': 'Romania',
  'RS': 'Serbia',
  'RU': 'Russian Federation',
  'RW': 'Rwanda',
  'SA': 'Saudi Arabia',
  'SB': 'Solomon Islands',
  'SC': 'Seychelles',
  'SD': 'Sudan',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'SH': 'Saint Helena, Ascension and Tristan da Cunha',
  'SI': 'Slovenia',
  'SJ': 'Svalbard and Jan Mayen',
  'SK': 'Slovakia',
  'SL': 'Sierra Leone',
  'SM': 'San Marino',
  'SN': 'Senegal',
  'SO': 'Somalia',
  'SR': 'Suriname',
  'SS': 'South Sudan',
  'ST': 'Sao Tome and Principe',
  'SV': 'El Salvador',
  'SX': 'Sint Maarten (Dutch part)',
  'SY': 'Syrian Arab Republic',
  'SZ': 'Eswatini',
  'TC': 'Turks and Caicos Islands',
  'TD': 'Chad',
  'TF': 'French Southern Territories',
  'TG': 'Togo',
  'TH': 'Thailand',
  'TJ': 'Tajikistan',
  'TK': 'Tokelau',
  'TL': 'Timor-Leste',
  'TM': 'Turkmenistan',
  'TN': 'Tunisia',
  'TO': 'Tonga',
  'TR': 'Türkiye',
  'TT': 'Trinidad and Tobago',
  'TV': 'Tuvalu',
  'TW': 'Taiwan, Province of China',
  'TZ': 'Tanzania, United Republic of',
  'UA': 'Ukraine',
  'UG': 'Uganda',
  'UM': 'United States Minor Outlying Islands',
  'US': 'United States of America',
  'UY': 'Uruguay',
  'UZ': 'Uzbekistan',
  'VA': 'Holy See',
  'VC': 'Saint Vincent and the Grenadines',
  'VE': 'Venezuela, Bolivarian Republic of',
  'VG': 'Virgin Islands (British)',
  'VI': 'Virgin Islands (U.S.)',
  'VN': 'Viet Nam',
  'VU': 'Vanuatu',
  'WF': 'Wallis and Futuna',
  'WS': 'Samoa',
  'YE': 'Yemen',
  'YT': 'Mayotte',
  'ZA': 'South Africa',
  'ZM': 'Zambia',
  'ZW': 'Zimbabwe',
};

/// All ISO 3166-1 alpha-2 codes with English labels in this map, sorted by
/// [regionDisplayNameEnglish] (for filter chip lists).
List<({String code, String displayName})> sortedSupportedIso3166Alpha2Countries() {
  final keys = _kIso3166Alpha2English.keys.toList();
  keys.sort((a, b) {
    final na = regionDisplayNameEnglish(a).toLowerCase();
    final nb = regionDisplayNameEnglish(b).toLowerCase();
    final cmp = na.compareTo(nb);
    return cmp != 0 ? cmp : a.compareTo(b);
  });
  return [
    for (final k in keys) (code: k, displayName: regionDisplayNameEnglish(k)),
  ];
}
