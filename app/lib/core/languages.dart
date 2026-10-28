/// Languages BookIt can translate into and out of.
///
/// `code` is the FLORES-200 code used by the NLLB-200 model
/// (language + script), e.g. `tam_Taml` for Tamil in Tamil script.
class Language {
  final String code;
  final String name; // English name
  final String nativeName;
  final LanguageGroup group;
  final String? iso1; // ISO 639-1 code used by Project Gutenberg, if any

  const Language(this.code, this.name, this.nativeName, this.group, [this.iso1]);

  String get script => code.split('_').last;
  bool get isRtl => const {'Arab', 'Hebr', 'Thaa', 'Syrc'}.contains(script);

  /// "Tamil · தமிழ்"
  String get label => nativeName == name ? name : '$name · $nativeName';

  @override
  bool operator ==(Object other) => other is Language && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

enum LanguageGroup { indian, european, world }

extension LanguageGroupLabel on LanguageGroup {
  String get label => switch (this) {
        LanguageGroup.indian => 'Indian languages',
        LanguageGroup.european => 'European languages',
        LanguageGroup.world => 'More languages',
      };
}

const _i = LanguageGroup.indian;
const _e = LanguageGroup.european;
const _w = LanguageGroup.world;

/// Ordered list shown in pickers. Every code here must exist in the NLLB
/// tokenizer (checked by test/languages_test.dart against reference data).
const List<Language> kLanguages = [
  // ---- Indian languages (scheduled languages covered by NLLB-200) ----
  Language('hin_Deva', 'Hindi', 'हिन्दी', _i, 'hi'),
  Language('ben_Beng', 'Bengali', 'বাংলা', _i, 'bn'),
  Language('tel_Telu', 'Telugu', 'తెలుగు', _i, 'te'),
  Language('mar_Deva', 'Marathi', 'मराठी', _i, 'mr'),
  Language('tam_Taml', 'Tamil', 'தமிழ்', _i, 'ta'),
  Language('urd_Arab', 'Urdu', 'اردو', _i, 'ur'),
  Language('guj_Gujr', 'Gujarati', 'ગુજરાતી', _i, 'gu'),
  Language('kan_Knda', 'Kannada', 'ಕನ್ನಡ', _i, 'kn'),
  Language('mal_Mlym', 'Malayalam', 'മലയാളം', _i, 'ml'),
  Language('ory_Orya', 'Odia', 'ଓଡ଼ିଆ', _i, 'or'),
  Language('pan_Guru', 'Punjabi', 'ਪੰਜਾਬੀ', _i, 'pa'),
  Language('asm_Beng', 'Assamese', 'অসমীয়া', _i, 'as'),
  Language('mai_Deva', 'Maithili', 'मैथिली', _i),
  Language('san_Deva', 'Sanskrit', 'संस्कृतम्', _i, 'sa'),
  Language('npi_Deva', 'Nepali', 'नेपाली', _i, 'ne'),
  Language('snd_Arab', 'Sindhi', 'سنڌي', _i, 'sd'),
  Language('kas_Arab', 'Kashmiri (Arabic)', 'کٲشُر', _i, 'ks'),
  Language('kas_Deva', 'Kashmiri (Devanagari)', 'कॉशुर', _i),
  Language('mni_Beng', 'Manipuri (Meitei)', 'মৈতৈলোন্', _i),
  Language('sat_Olck', 'Santali', 'ᱥᱟᱱᱛᱟᱲᱤ', _i),
  // ---- European languages ----
  Language('eng_Latn', 'English', 'English', _e, 'en'),
  Language('fra_Latn', 'French', 'Français', _e, 'fr'),
  Language('deu_Latn', 'German', 'Deutsch', _e, 'de'),
  Language('spa_Latn', 'Spanish', 'Español', _e, 'es'),
  Language('ita_Latn', 'Italian', 'Italiano', _e, 'it'),
  Language('por_Latn', 'Portuguese', 'Português', _e, 'pt'),
  Language('nld_Latn', 'Dutch', 'Nederlands', _e, 'nl'),
  Language('pol_Latn', 'Polish', 'Polski', _e, 'pl'),
  Language('rus_Cyrl', 'Russian', 'Русский', _e, 'ru'),
  Language('ukr_Cyrl', 'Ukrainian', 'Українська', _e, 'uk'),
  Language('ell_Grek', 'Greek', 'Ελληνικά', _e, 'el'),
  Language('ron_Latn', 'Romanian', 'Română', _e, 'ro'),
  Language('ces_Latn', 'Czech', 'Čeština', _e, 'cs'),
  Language('slk_Latn', 'Slovak', 'Slovenčina', _e, 'sk'),
  Language('hun_Latn', 'Hungarian', 'Magyar', _e, 'hu'),
  Language('swe_Latn', 'Swedish', 'Svenska', _e, 'sv'),
  Language('dan_Latn', 'Danish', 'Dansk', _e, 'da'),
  Language('nob_Latn', 'Norwegian', 'Norsk bokmål', _e, 'no'),
  Language('fin_Latn', 'Finnish', 'Suomi', _e, 'fi'),
  Language('est_Latn', 'Estonian', 'Eesti', _e, 'et'),
  Language('lvs_Latn', 'Latvian', 'Latviešu', _e, 'lv'),
  Language('lit_Latn', 'Lithuanian', 'Lietuvių', _e, 'lt'),
  Language('bul_Cyrl', 'Bulgarian', 'Български', _e, 'bg'),
  Language('srp_Cyrl', 'Serbian', 'Српски', _e, 'sr'),
  Language('hrv_Latn', 'Croatian', 'Hrvatski', _e, 'hr'),
  Language('slv_Latn', 'Slovenian', 'Slovenščina', _e, 'sl'),
  Language('mkd_Cyrl', 'Macedonian', 'Македонски', _e, 'mk'),
  Language('bel_Cyrl', 'Belarusian', 'Беларуская', _e, 'be'),
  Language('cat_Latn', 'Catalan', 'Català', _e, 'ca'),
  Language('eus_Latn', 'Basque', 'Euskara', _e, 'eu'),
  Language('glg_Latn', 'Galician', 'Galego', _e, 'gl'),
  Language('gle_Latn', 'Irish', 'Gaeilge', _e, 'ga'),
  Language('cym_Latn', 'Welsh', 'Cymraeg', _e, 'cy'),
  Language('isl_Latn', 'Icelandic', 'Íslenska', _e, 'is'),
  Language('mlt_Latn', 'Maltese', 'Malti', _e, 'mt'),
  Language('als_Latn', 'Albanian', 'Shqip', _e, 'sq'),
  Language('tur_Latn', 'Turkish', 'Türkçe', _e, 'tr'),
  Language('epo_Latn', 'Esperanto', 'Esperanto', _e, 'eo'),
  // ---- More languages ----
  Language('arb_Arab', 'Arabic', 'العربية', _w, 'ar'),
  Language('pes_Arab', 'Persian', 'فارسی', _w, 'fa'),
  Language('heb_Hebr', 'Hebrew', 'עברית', _w, 'he'),
  Language('zho_Hans', 'Chinese (Simplified)', '简体中文', _w, 'zh'),
  Language('zho_Hant', 'Chinese (Traditional)', '繁體中文', _w),
  Language('jpn_Jpan', 'Japanese', '日本語', _w, 'ja'),
  Language('kor_Hang', 'Korean', '한국어', _w, 'ko'),
  Language('vie_Latn', 'Vietnamese', 'Tiếng Việt', _w, 'vi'),
  Language('tha_Thai', 'Thai', 'ไทย', _w, 'th'),
  Language('ind_Latn', 'Indonesian', 'Bahasa Indonesia', _w, 'id'),
  Language('zsm_Latn', 'Malay', 'Bahasa Melayu', _w, 'ms'),
  Language('tgl_Latn', 'Tagalog', 'Tagalog', _w, 'tl'),
  Language('sin_Sinh', 'Sinhala', 'සිංහල', _w, 'si'),
  Language('mya_Mymr', 'Burmese', 'မြန်မာ', _w, 'my'),
  Language('khm_Khmr', 'Khmer', 'ខ្មែរ', _w, 'km'),
  Language('lao_Laoo', 'Lao', 'ລາວ', _w, 'lo'),
  Language('swh_Latn', 'Swahili', 'Kiswahili', _w, 'sw'),
  Language('amh_Ethi', 'Amharic', 'አማርኛ', _w, 'am'),
  Language('hau_Latn', 'Hausa', 'Hausa', _w, 'ha'),
  Language('yor_Latn', 'Yoruba', 'Yorùbá', _w, 'yo'),
  Language('ibo_Latn', 'Igbo', 'Igbo', _w, 'ig'),
  Language('zul_Latn', 'Zulu', 'isiZulu', _w, 'zu'),
  Language('afr_Latn', 'Afrikaans', 'Afrikaans', _w, 'af'),
  Language('kat_Geor', 'Georgian', 'ქართული', _w, 'ka'),
  Language('hye_Armn', 'Armenian', 'Հայերեն', _w, 'hy'),
  Language('azj_Latn', 'Azerbaijani', 'Azərbaycanca', _w, 'az'),
  Language('kaz_Cyrl', 'Kazakh', 'Қазақша', _w, 'kk'),
  Language('uzn_Latn', 'Uzbek', 'Oʻzbekcha', _w, 'uz'),
  Language('khk_Cyrl', 'Mongolian', 'Монгол', _w, 'mn'),
  Language('pbt_Arab', 'Pashto', 'پښتو', _w, 'ps'),
];

Language? languageByCode(String? code) {
  if (code == null) return null;
  for (final l in kLanguages) {
    if (l.code == code) return l;
  }
  return null;
}

/// Maps an ISO 639-1 code (as used by Project Gutenberg / EPUB metadata,
/// possibly with a region like `en-US`) to a BookIt language.
Language? languageByIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final base = iso.toLowerCase().split(RegExp('[-_]')).first;
  for (final l in kLanguages) {
    if (l.iso1 == base) return l;
  }
  return null;
}

const englishLanguage = Language('eng_Latn', 'English', 'English', _e, 'en');
