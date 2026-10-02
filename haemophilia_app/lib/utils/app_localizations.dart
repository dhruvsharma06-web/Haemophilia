import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central localization controller for HaemoPhysio.
class AppLocaleService {
  static const String _prefKey = 'haemophysio_app_language';
  static final ValueNotifier<String> currentLocale = ValueNotifier<String>('en');

  /// Initialize from local device storage on app startup.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'hi' || saved == 'en') {
        currentLocale.value = saved!;
      }
    } catch (e) {
      debugPrint('LocaleService init error: $e');
    }
  }

  /// Change app language immediately in memory and persist locally.
  static void setLocale(String langCode) {
    if (langCode != 'en' && langCode != 'hi') return;
    if (currentLocale.value == langCode) return;
    currentLocale.value = langCode;
    if (Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) FirebaseFirestore.instance.collection('users').doc(uid).update({'language': langCode}).catchError((Object e) { debugPrint('Could not save notification language: $e'); });
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefKey, langCode);
    }).catchError((e) {
      debugPrint('LocaleService setLocale error: $e');
    });
  }

  /// Convenience boolean.
  static bool get isHindi => currentLocale.value == 'hi';

  /// Toggle between English and Hindi.
  static void toggle() {
    setLocale(isHindi ? 'en' : 'hi');
  }
}

/// Inherited widget that establishes a reactive dependency on the active app locale.
/// Any widget whose `build` method calls `AppLocaleScope.of(context)` will instantly
/// rebuild when the user switches between English and Hindi.
class AppLocaleScope extends InheritedNotifier<ValueNotifier<String>> {
  const AppLocaleScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static String of([BuildContext? context]) {
    if (context == null) return AppLocaleService.currentLocale.value;
    final scope = context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    return scope?.notifier?.value ?? AppLocaleService.currentLocale.value;
  }
}

/// Global translation helper function.
/// Returns the translated text in Hindi if Hindi is active, otherwise returns [key].
/// When [context] is provided, establishes an active rebuild dependency.
String tr(String key, [BuildContext? context]) {
  if (context != null) {
    AppLocaleScope.of(context);
  }
  if (!AppLocaleService.isHindi) return key;
  if (_hindiTranslations.containsKey(key)) {
    return _hindiTranslations[key]!;
  }
  final trimmed = key.trim();
  if (_hindiTranslations.containsKey(trimmed)) {
    return _hindiTranslations[trimmed]!;
  }
  final lower = key.toLowerCase().trim();
  final normalized = _normalizedHindiTranslations[lower];
  if (normalized != null) return normalized;
  final prefixes = <String, String>{
    'Could not load users.': 'उपयोगकर्ता नहीं मिले।', 'Could not load patient data.': 'मरीज़ का डेटा नहीं मिला।',
    'Could not load messages.': 'संदेश नहीं मिले।', 'Could not load doctors.': 'डॉक्टर की सूची नहीं मिली।',
    'Could not load your session history.': 'सत्र का इतिहास नहीं मिला।',
    'Could not load account details for ': 'खाते की जानकारी नहीं मिली: ',
    'Could not send message: ': 'संदेश नहीं भेजा जा सका: ', 'Could not save assignment: ': 'व्यायाम नहीं सहेजा जा सका: ',
    'Could not update user: ': 'खाता अपडेट नहीं हुआ: ', 'Could not update profile: ': 'प्रोफ़ाइल अपडेट नहीं हुई: ',
    'Assessment result could not be saved: ': 'मूल्यांकन नहीं सहेजा जा सका: ',
    'Enter a valid target for ': 'सही लक्ष्य दर्ज करें: ',
    'Ready to begin: ': 'शुरू करने के लिए तैयार: ', 'Ready to continue: ': 'जारी रखने के लिए तैयार: ',
    'Target: ': 'लक्ष्य: ', 'Session ': 'सत्र ', 'Session 1': 'सत्र 1',
    'Assessment consistency: ': 'मूल्यांकन की संगति: ',
  };
  for (final entry in prefixes.entries) { if (key.startsWith(entry.key)) return entry.value + key.substring(entry.key.length); }
  return key;
}

/// Extension on BuildContext for effortless translation binding: `context.tr('Hello')`.
extension AppLocalizationsContextX on BuildContext {
  String tr(String key) => appLocalizationsTr(key, this);
}

String appLocalizationsTr(String key, BuildContext context) => tr(key, context);

/// String extension for convenience syntax: `'Assigned Patients'.tr`.
extension TranslationExtension on String {
  String get tr => AppLocaleService.isHindi ? (_hindiTranslations[this] ?? _hindiTranslations[trim()] ?? this) : this;
}

/// Helper function to translate Firestore status strings to user-facing labels.
String trStatus(String? status) {
  if (status == null || status.isEmpty) return '';
  final s = status.toLowerCase().trim();
  if (AppLocaleService.isHindi) {
    switch (s) {
      case 'completed':
        return 'पूर्ण';
      case 'in_progress':
      case 'active':
        return 'प्रगति पर';
      case 'paused':
        return 'रोका हुआ';
      case 'assigned':
        return 'असाइन किया गया';
      case 'pending':
        return 'लंबित';
      case 'discarded':
        return 'अस्वीकृत';
      case 'abandoned':
        return 'अधूरा';
      default:
        return s;
    }
  } else {
    switch (s) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
      case 'active':
        return 'In Progress';
      case 'paused':
        return 'Paused';
      case 'assigned':
        return 'Assigned';
      case 'pending':
        return 'Pending';
      case 'discarded':
        return 'Discarded';
      case 'abandoned':
        return 'Abandoned';
      default:
        return status;
    }
  }
}

/// Compact, elegant language switch widget for AppBars and navigation bars.
class LanguageToggleButton extends StatelessWidget {
  final Color? color;
  final Color? backgroundColor;

  const LanguageToggleButton({
    super.key,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final effectiveColor = color ?? themePrimary;

    return ValueListenableBuilder<String>(
      valueListenable: AppLocaleService.currentLocale,
      builder: (context, locale, _) {
        final isHindi = locale == 'hi';

        return Tooltip(
          message: isHindi ? 'Switch to English' : 'हिन्दी में बदलें',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => AppLocaleService.toggle(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              decoration: BoxDecoration(
                color: backgroundColor ?? effectiveColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: effectiveColor.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 15,
                    color: effectiveColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isHindi ? 'हिन्दी' : 'English',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: effectiveColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Natural and readable Hindi translations dictionary.
/// Technical names, usernames, exercise identifiers and numeric scores remain untranslated.
const Map<String, String> _hindiTranslations = {
  "View": "देखें",
  "Access is unavailable. Please contact the administrator.": "पहुँच उपलब्ध नहीं है। कृपया प्रशासक से संपर्क करें।",
  "This feature is being configured. Please contact the administrator.": "यह सुविधा तैयार की जा रही है। कृपया प्रशासक से संपर्क करें।",
  "Check your internet connection and try again.": "इंटरनेट कनेक्शन जाँचें और फिर प्रयास करें।",
  "Your sign-in has expired. Please sign in again.": "आपका साइन-इन समाप्त हो गया है। कृपया दोबारा साइन-इन करें।",
  "This record is no longer available. Refresh and try again.": "यह रिकॉर्ड अब उपलब्ध नहीं है। रिफ्रेश करें और फिर प्रयास करें।",
  "Patient screening": "मरीज़ की प्रारंभिक जाँच",
  "AI screening result": "AI प्रारंभिक जाँच का परिणाम",
  "Biological sex": "जैविक लिंग",
  "Bleeding after minor cuts": "छोटे कट के बाद रक्तस्राव",
  "Bleeding after surgery or stitches": "सर्जरी या टांके के बाद रक्तस्राव",
  "Bleeding after dental procedures": "दंत चिकित्सा के बाद रक्तस्राव",
  "Easy or unusual bruising": "आसानी से या असामान्य नील पड़ना",
  "Unexplained muscle swelling or pain": "बिना स्पष्ट कारण मांसपेशियों में सूजन या दर्द",
  "Repeated joint swelling or bleeding": "जोड़ों में बार-बार सूजन या रक्तस्राव",
  "Warmth around the affected joint": "प्रभावित जोड़ के आसपास गर्माहट",
  "Joint tightness or stiffness": "जोड़ में जकड़न या अकड़न",
  "Reduced joint mobility": "जोड़ की गतिशीलता में कमी",
  "Blood in urine": "मूत्र में रक्त",
  "Blood in stool": "मल में रक्त",
  "Family history of a bleeding disorder": "परिवार में रक्तस्राव विकार का इतिहास",
  "Male relative diagnosed with haemophilia": "हीमोफीलिया से पीड़ित पुरुष रिश्तेदार",
  "Previous clotting factor test": "पहले की गई क्लॉटिंग फैक्टर जाँच",
  "This is an automated screening estimate, not a diagnosis. Review the reported symptoms and arrange appropriate clinical evaluation.": "यह स्वचालित प्रारंभिक जाँच का अनुमान है, निदान नहीं। बताए गए लक्षणों की समीक्षा करें और उचित चिकित्सकीय जाँच की व्यवस्था करें।",
  "The patient reports an existing diagnosis. The screening questionnaire was not repeated.": "मरीज़ ने पहले से हुए निदान की जानकारी दी है। प्रारंभिक जाँच के प्रश्न दोबारा नहीं पूछे गए।",
  "The patient has not completed screening yet.": "मरीज़ ने अभी प्रारंभिक जाँच पूरी नहीं की है।",
  "Could not load patient screening.": "मरीज़ की प्रारंभिक जाँच की जानकारी नहीं मिली।",
  "Could not save assignment. Please try again.": "व्यायाम निर्धारित नहीं किया जा सका। कृपया फिर प्रयास करें।",
  "Could not update user. Please try again.": "खाता अपडेट नहीं हुआ। कृपया फिर प्रयास करें।",
  "Could not update profile. Please try again.": "प्रोफ़ाइल अपडेट नहीं हुई। कृपया फिर प्रयास करें।",
  "Could not send message. Please try again.": "संदेश नहीं भेजा जा सका। कृपया फिर प्रयास करें।",
  "This is a doctor account. Please use Doctor Login.": "यह डॉक्टर का खाता है। कृपया डॉक्टर लॉगिन का उपयोग करें।",
  "This is a patient account. Please use Patient Login.": "यह मरीज़ का खाता है। कृपया मरीज़ लॉगिन का उपयोग करें।",
  "Doctor account creation is currently unavailable. Please contact support.": "डॉक्टर का नया खाता बनाना अभी उपलब्ध नहीं है। कृपया सहायता से संपर्क करें।",
  "Your doctor will appear here once assigned. You can contact the administrator from Help.": "डॉक्टर नियुक्त होने पर यहाँ दिखेंगे। सहायता अनुभाग से प्रशासक से संपर्क कर सकते हैं।",
  "This time is already selected.": "यह समय पहले से चुना गया है।",
  "Daily session times": "दिन में सत्र के समय",
  "Add another time": "एक और समय जोड़ें",
  "Select 1–366 days, at least one weekday and unique daily session times.": "1–366 दिन, कम से कम एक सप्ताह का दिन और अलग-अलग सत्र के समय चुनें।",
  "Your account information, screening answers, messages and exercise results are stored to provide the service. Relevant care records are available to your assigned doctor and authorized administrators as part of your care. Camera processing is confirmed separately before each session.": "सेवा देने के लिए आपके खाते की जानकारी, जाँच के उत्तर, संदेश और व्यायाम के परिणाम सुरक्षित रखे जाते हैं। आपकी देखभाल के लिए संबंधित रिकॉर्ड नियुक्त डॉक्टर और अधिकृत प्रशासकों को उपलब्ध होते हैं। हर सत्र से पहले कैमरा प्रोसेसिंग की सहमति अलग से ली जाती है।",
  "Your professional profile and messages are stored to provide the service. Administrators review doctor applications. Only access records for patients assigned to your care.": "सेवा देने के लिए आपकी पेशेवर प्रोफ़ाइल और संदेश सुरक्षित रखे जाते हैं। प्रशासक डॉक्टर के आवेदन की समीक्षा करते हैं। केवल अपनी देखभाल में नियुक्त मरीज़ों के रिकॉर्ड देखें।",
  "Specialization": "विशेषज्ञता",
  "Hospital / Clinic": "अस्पताल / क्लिनिक",
  "Save and exit": "सहेजें और बाहर जाएँ",
  "Great job! You have completed all exercises for": "आपने सभी व्यायाम पूरे कर लिए हैं:",
  "You have not completed all exercises for": "आपने सभी व्यायाम पूरे नहीं किए हैं:",
  'Perform the prescribed movement smoothly through your safe range of motion.': 'निर्धारित गतिविधि अपनी सुरक्षित सीमा में धीरे और सहज तरीके से करें।',
  'Return with control to starting position and prepare for next rep.': 'नियंत्रित तरीके से शुरुआती स्थिति में लौटें और अगले दोहराव की तैयारी करें।',
  'Your progress is still on this screen. Restore your connection, then retry saving.': 'आपकी प्रगति इस स्क्रीन पर है। कनेक्शन ठीक होने पर फिर से सहेजें।',
  'Please enter an age from 1 to 120.': 'कृपया 1 से 120 के बीच आयु दर्ज करें।',
  'Starting Position': 'शुरुआती स्थिति', 'Upward Movement': 'ऊपर उठाना', 'Overhead Position': 'सिर के ऊपर की स्थिति',
  'Downward Movement': 'नीचे लाना', 'Return to Start': 'शुरुआती स्थिति में लौटें',
  'Outward Rotation': 'बाहर की ओर घुमाना', 'Peak External Rotation': 'बाहर घुमाने की अंतिम स्थिति', 'Inward Return': 'अंदर की ओर लौटना',
  'Assisted Bending': 'सहारे से मोड़ना', 'Peak Flexion': 'अधिकतम आरामदायक मोड़', 'Controlled Lowering': 'नियंत्रित तरीके से नीचे लाना',
  'Bending (Flexion)': 'मोड़ना', 'Straightening (Extension)': 'सीधा करना', 'Exercise Movement': 'व्यायाम की गतिविधि', 'Return to Rest': 'आराम की स्थिति में लौटें',
  'Begin in standard ready position.': 'आरामदायक शुरुआती स्थिति में आएँ।',
  'Hold the bar horizontally with both hands at thigh level. Keep your back straight, chest open, and shoulders relaxed.': 'बार को दोनों हाथों से जाँघों के सामने सीधा पकड़ें। पीठ सीधी, छाती खुली और कंधे आरामदायक रखें।',
  'Slowly raise both arms forward and upward together. Keep elbows straight and use the unaffected arm to guide the movement.': 'दोनों हाथों को एक साथ धीरे-धीरे आगे और ऊपर उठाएँ। कोहनियाँ सीधी रखें और स्वस्थ हाथ से गति में सहारा दें।',
  'Hold briefly at the comfortable top position. Maintain an upright posture and avoid arching your lower back.': 'आरामदायक ऊपरी स्थिति में थोड़ी देर रुकें। शरीर सीधा रखें और कमर पीछे न मोड़ें।',
  'Lower the bar smoothly along the same arc with steady control. Do not let the arms drop suddenly.': 'बार को उसी रास्ते से धीरे-धीरे नियंत्रित तरीके से नीचे लाएँ। हाथ अचानक न गिरने दें।',
  'Pause momentarily in the starting position before beginning the next repetition.': 'अगला दोहराव शुरू करने से पहले शुरुआती स्थिति में थोड़ी देर रुकें।',
  'Keep both hands evenly spaced on the bar.': 'बार पर दोनों हाथ समान दूरी पर रखें।',
  'Maintain steady breathing — inhale on lift, exhale on lower.': 'साँस सामान्य रखें — उठाते समय साँस लें और नीचे लाते समय छोड़ें।',
  'Do not lean back or shrug your shoulders.': 'पीछे न झुकें और कंधे न उचकाएँ।',
  'Stop if you experience sharp joint pain.': 'जोड़ में तेज दर्द होने पर रुकें।',
  'Stand upright facing forward with elbows bent at 90° tucked closely against your torso, forearms pointing straight forward.': 'सामने की ओर सीधे खड़े हों। कोहनियाँ 90° पर मोड़कर शरीर के पास रखें और अग्रबाहु सामने की ओर रखें।',
  'Slowly rotate both forearms outward away from the midline while keeping elbows pinned firmly against your sides.': 'कोहनियों को शरीर के पास रखते हुए दोनों अग्रबाहुओं को धीरे-धीरे बाहर की ओर घुमाएँ।',
  'Hold momentarily at your comfortable, pain-free outward rotation limit without twisting your torso.': 'शरीर मोड़े बिना आरामदायक, दर्दरहित बाहरी स्थिति में थोड़ी देर रुकें।',
  'Smoothly rotate forearms back toward the center with steady, controlled motion.': 'अग्रबाहुओं को नियंत्रित तरीके से धीरे-धीरे बीच की ओर वापस लाएँ।',
  'Pause momentarily in the neutral starting position before beginning the next repetition.': 'अगला दोहराव शुरू करने से पहले सामान्य शुरुआती स्थिति में थोड़ी देर रुकें।',
  'Keep elbows firmly pinned against your ribs throughout the entire movement.': 'पूरी गतिविधि के दौरान कोहनियाँ पसलियों के पास रखें।',
  'Maintain an upright posture without leaning or twisting your chest.': 'छाती मोड़े या झुके बिना शरीर सीधा रखें।',
  'Work strictly within your comfortable, pain-free range of motion.': 'केवल आरामदायक और दर्दरहित सीमा में गतिविधि करें।',
  'Follow your clinician’s guidance on repetition targets and pacing.': 'दोहराव की संख्या और गति के बारे में अपने चिकित्सक के निर्देश मानें।',
  'Keep active arm relaxed at your side with the opposite hand gently supporting under the wrist or forearm.': 'व्यायाम वाला हाथ बगल में आराम से रखें और दूसरे हाथ से कलाई या अग्रबाहु के नीचे हल्का सहारा दें।',
  'Use your supporting hand to guide and gently assist bending the recovering elbow upward.': 'सहारा देने वाले हाथ से प्रभावित कोहनी को धीरे-धीरे ऊपर मोड़ने में मदद करें।',
  'Pause briefly at the top position where the hand approaches shoulder height without strain.': 'बिना खिंचाव के हाथ कंधे की ऊँचाई के पास आने पर थोड़ी देर रुकें।',
  'Carefully lower the forearm back down with the supporting hand guiding the descent smoothly.': 'सहारा देने वाले हाथ की मदद से अग्रबाहु को सावधानीपूर्वक धीरे-धीरे नीचे लाएँ।',
  'Fully relax at the starting extension before beginning the next repetition.': 'अगला दोहराव शुरू करने से पहले शुरुआती सीधी स्थिति में पूरी तरह आराम करें।',
  'Use your opposite hand to take weight off the recovering joint.': 'प्रभावित जोड़ का भार कम करने के लिए दूसरे हाथ से सहारा दें।',
  'Keep the upper arm still and avoid swinging your elbow forward.': 'ऊपरी बाँह स्थिर रखें और कोहनी आगे न झुलाएँ।',
  'Move slowly and stop immediately if sharp discomfort occurs.': 'धीरे चलें और तेज असुविधा होने पर तुरंत रुकें।',
  'Hold arm at side with elbow extended, palm facing forward.': 'हाथ बगल में रखें, कोहनी सीधी और हथेली सामने की ओर रखें।',
  'Smoothly bend the elbow upward, keeping upper arm still against torso.': 'ऊपरी बाँह शरीर के पास स्थिर रखते हुए कोहनी धीरे-धीरे ऊपर मोड़ें।',
  'Briefly hold at top with hand approaching shoulder height.': 'हाथ कंधे की ऊँचाई के पास आने पर ऊपरी स्थिति में थोड़ी देर रुकें।',
  'Lower forearm back down with steady control to starting position.': 'अग्रबाहु को नियंत्रित तरीके से धीरे-धीरे शुरुआती स्थिति में नीचे लाएँ।',
  'Pause briefly before beginning next repetition.': 'अगला दोहराव शुरू करने से पहले थोड़ी देर रुकें।',
  'Keep upper arm locked beside your torso.': 'ऊपरी बाँह शरीर के पास स्थिर रखें।',
  'Perform movement smoothly without swinging.': 'बिना झुलाए गतिविधि सहज तरीके से करें।',
  'Work within comfortable pain-free range.': 'आरामदायक, दर्दरहित सीमा में गतिविधि करें।',
  'Assume a relaxed, upright posture facing the camera directly.': 'कैमरे की ओर सीधे देखकर आरामदायक, सीधी मुद्रा में आएँ।',
  'Get ready — raise your arm.': 'तैयार हों — हाथ उठाएँ।',
  'Perform a repetition.': 'एक दोहराव करें।',
  'Move into the camera view.': 'कैमरे के सामने आएँ।',
  'Raise your arm higher.': 'हाथ थोड़ा और ऊपर उठाएँ।',
  'Good height — now lower your arm slowly.': 'ऊँचाई ठीक है — अब हाथ धीरे-धीरे नीचे लाएँ।',
  'Good, keep raising your arm higher.': 'ठीक है, हाथ और ऊपर उठाते रहें।',
  'Incorrect: your body tilted during the repetition. Keep your torso upright throughout the movement.': 'गलत: दोहराव के दौरान शरीर झुका। पूरी गतिविधि में शरीर सीधा रखें।',
  'Almost there — raise your arm a little higher.': 'लगभग पूरा है — हाथ थोड़ा और ऊपर उठाएँ।',
  'Incorrect: one arm did not stay level with the other. Raise both arms together without tilting the bar.': 'गलत: दोनों हाथ समान ऊँचाई पर नहीं रहे। बार झुकाए बिना दोनों हाथ साथ उठाएँ।',
  'Keep following the exercise instructions.': 'व्यायाम के निर्देशों का पालन करते रहें।',
  'RIGHT ARM TOO LOW': 'दाहिना हाथ बहुत नीचे है', 'LEFT ARM TOO LOW': 'बायाँ हाथ बहुत नीचे है',
  'ARMS NOT SYMMETRIC': 'दोनों हाथ समान नहीं हैं', 'BODY TILT DETECTED': 'शरीर झुक रहा है',
  'ELBOW FLARE DETECTED': 'कोहनी बाहर निकल रही है', 'TORSO ROTATION DETECTED': 'धड़ घूम रहा है',
  'INSUFFICIENT ELBOW FLEXION': 'कोहनी पर्याप्त नहीं मुड़ी', 'LIMITED RANGE OF MOTION': 'गतिविधि की सीमा कम है',
  'GENERAL FORM ERROR': 'व्यायाम की मुद्रा गलत है', 'AI Live': 'AI चालू है',
  'Patient ID': 'मरीज़ की पहचान',
  'Doctor approvals': 'डॉक्टर की स्वीकृति',
  'New patients': 'नए मरीज़',
  'Patients waiting for a doctor. Review screening and assign a clinician.': 'डॉक्टर की प्रतीक्षा कर रहे मरीज़। जाँच देखकर डॉक्टर नियुक्त करें।',
  'Review clinician applications before granting access.': 'पहुँच देने से पहले चिकित्सकों के आवेदन जाँचें।',
  'Manage existing accounts and doctor transfers.': 'मौजूदा खाते और डॉक्टर बदलाव प्रबंधित करें।',
  'No patients are waiting for a doctor.': 'किसी मरीज़ को डॉक्टर की प्रतीक्षा नहीं है।',
  'No doctor applications are waiting.': 'डॉक्टर का कोई आवेदन लंबित नहीं है।',
  'No approved doctors are available.': 'कोई स्वीकृत डॉक्टर उपलब्ध नहीं है।',
  'Assign doctor': 'डॉक्टर नियुक्त करें',
  'Approved doctor': 'स्वीकृत डॉक्टर',
  'Doctor assigned.': 'डॉक्टर नियुक्त हो गया है।',
  'This patient already has a doctor. Refresh the patient list.': 'इस मरीज़ को डॉक्टर नियुक्त हो चुका है। मरीज़ों की सूची फिर से खोलें।',
  'Firebase access settings are blocking patient assignment. Contact the project owner.': 'Firebase की पहुँच सेटिंग मरीज़ को डॉक्टर नियुक्त करने से रोक रही है। परियोजना मालिक से संपर्क करें।',
  'Registered': 'पंजीकरण',
  'Qualification': 'योग्यता',
  'patient': 'मरीज़', 'doctor': 'डॉक्टर', 'admin': 'प्रशासक', 'pending_doctor': 'डॉक्टर की स्वीकृति लंबित',
  'Your assigned doctor will appear here after administrator assignment.': 'प्रशासक की नियुक्ति के बाद आपका डॉक्टर यहाँ दिखाई देगा।',
  'Terms, privacy and consent': 'नियम, गोपनीयता और सहमति',
  'Somaiya HemoPhysio supports exercise guidance and progress monitoring. AI screening and movement feedback may be inaccurate and do not provide a diagnosis or replace your treating clinician. Follow your prescribed care plan and seek professional guidance when unsure.': 'Somaiya HemoPhysio व्यायाम मार्गदर्शन और प्रगति देखने में मदद करता है। AI जाँच और गतिविधि की प्रतिक्रिया गलत हो सकती है। यह निदान नहीं करती और आपके चिकित्सक का स्थान नहीं लेती। अपनी निर्धारित देखभाल योजना का पालन करें और संदेह होने पर चिकित्सक से सलाह लें।',
  'Your account information, screening answers, messages and exercise results are stored to provide the service. Your assigned doctor and authorized administrators can review relevant records. Camera frames are sent to the assessment server for pose processing during a session.': 'सेवा प्रदान करने के लिए आपके खाते की जानकारी, जाँच के उत्तर, संदेश और व्यायाम के परिणाम सहेजे जाते हैं। आपके निर्धारित डॉक्टर और अधिकृत प्रशासक संबंधित रिकॉर्ड देख सकते हैं। सत्र के दौरान शारीरिक मुद्रा का विश्लेषण करने के लिए कैमरे की छवियाँ मूल्यांकन सर्वर को भेजी जाती हैं।',
  'Use accurate information, keep your login private and use messaging respectfully. You remain responsible for deciding when to stop and seeking medical help. Do not exercise while bleeding or continue through concerning symptoms.': 'सही जानकारी दें, अपनी लॉगिन जानकारी निजी रखें और संदेशों में सम्मानजनक भाषा प्रयोग करें। व्यायाम कब रोकना है और चिकित्सा सहायता कब लेनी है, यह निर्णय आपकी जिम्मेदारी है। रक्तस्राव के दौरान व्यायाम न करें और चिंताजनक लक्षण होने पर रुकें।',
  'I accept the terms and acknowledge the privacy information.': 'मैं नियम स्वीकार करता/करती हूँ और गोपनीयता की जानकारी समझता/समझती हूँ।',
  'I consent to assessment data processing and understand the limitations of AI feedback.': 'मैं मूल्यांकन डेटा के विश्लेषण की सहमति देता/देती हूँ और AI प्रतिक्रिया की सीमाएँ समझता/समझती हूँ।',
  'Optional: I allow my assessment and screening data to be used for research and development.': 'वैकल्पिक: मैं अपने मूल्यांकन और जाँच डेटा को अनुसंधान और विकास में इस्तेमाल करने की अनुमति देता/देती हूँ।',
  'Declining does not prevent access. You can change this choice in Help.': 'मना करने पर भी ऐप का उपयोग कर सकते हैं। सहायता अनुभाग में यह विकल्प बदल सकते हैं।',
  'Before you start': 'शुरू करने से पहले',
  'If you are bleeding or suspect bleeding, do not start. Stop immediately if bleeding occurs during exercise and contact your treating doctor before proceeding.': 'रक्तस्राव हो रहा हो या उसकी आशंका हो तो शुरू न करें। व्यायाम के दौरान रक्तस्राव होने पर तुरंत रुकें और आगे बढ़ने से पहले अपने चिकित्सक से संपर्क करें।',
  'Camera frames are sent for AI movement assessment. AI feedback can be incorrect and is not a medical diagnosis. Follow your clinician’s instructions and stop if you feel unwell.': 'AI से गतिविधि का मूल्यांकन करने के लिए कैमरे की छवियाँ भेजी जाती हैं। AI प्रतिक्रिया गलत हो सकती है और यह चिकित्सा निदान नहीं है। अपने चिकित्सक के निर्देश मानें और अस्वस्थ महसूस होने पर रुकें।',
  'I am not bleeding and do not suspect bleeding.': 'मुझे रक्तस्राव नहीं हो रहा है और इसकी आशंका भी नहीं है।',
  'I consent to camera processing for this session and understand the AI limitations.': 'मैं इस सत्र में कैमरे की छवियों के विश्लेषण की सहमति देता/देती हूँ और AI की सीमाएँ समझता/समझती हूँ।',
  'Start session': 'सत्र शुरू करें',
  'Could not save. Please try again.': 'सहेजा नहीं जा सका। कृपया फिर प्रयास करें।',
  'Grievances': 'शिकायतें',
  'Manage accounts, doctor assignments and platform access.': 'खाते, डॉक्टर नियुक्ति और ऐप की पहुँच प्रबंधित करें।',
  'Promote existing accounts and assign patients to doctors.': 'खातों की भूमिका बदलें और मरीज़ों को डॉक्टर नियुक्त करें।',
  'Manage': 'प्रबंधित करें',
  'Unassigned': 'अभी नियुक्त नहीं',
  'Account active': 'खाता सक्रिय है',
  'Set the role to Doctor to approve an application. Disable account access to remove a doctor while retaining records.': 'आवेदन स्वीकृत करने के लिए भूमिका डॉक्टर करें। रिकॉर्ड सुरक्षित रखते हुए डॉक्टर को हटाने के लिए खाते की पहुँच बंद करें।',
  'Screening answers': 'जाँच के उत्तर',
  'Assigned doctor': 'नियुक्त डॉक्टर',
  'User updated.': 'उपयोगकर्ता की जानकारी अपडेट हुई।',
  'No users found.': 'कोई उपयोगकर्ता नहीं मिला।',
  'What would you like to do?': 'आप क्या करना चाहेंगे?',
  'Your progress has been saved.': 'आपकी प्रगति सहेज ली गई है।',
  'User profile not found': 'उपयोगकर्ता की प्रोफ़ाइल नहीं मिली',
  'Sign out to try another account': 'दूसरे खाते के लिए साइन आउट करें',
  'Account inactive. Please contact the administrator.': 'खाता निष्क्रिय है। कृपया प्रशासक से संपर्क करें।',
  'Account access unavailable. Sign out and contact admin.': 'खाते की पहुँच उपलब्ध नहीं है। साइन आउट करके प्रशासक से संपर्क करें।',
  'Sign out': 'साइन आउट',
  'Invalid credentials or password.': 'लॉगिन जानकारी या पासवर्ड गलत है।',
  'No clinician account found with this ID.': 'इस पहचान से कोई चिकित्सक खाता नहीं मिला।',
  'An account already exists with this email address.': 'इस ईमेल पते से खाता पहले से मौजूद है।',
  'Registration failed. Please try again.': 'पंजीकरण नहीं हो सका। कृपया फिर प्रयास करें।',
  'Analyzing your responses...': 'आपके उत्तरों का विश्लेषण हो रहा है...',
  'Continue to app': 'ऐप में आगे बढ़ें',
  'Welcome': 'स्वागत है',
  'Have you been diagnosed with haemophilia?': 'क्या डॉक्टर ने आपको हीमोफीलिया होने की पुष्टि की है?',
  'Tell us about your health so an administrator can assign a doctor. This information does not establish a diagnosis.': 'अपनी स्वास्थ्य जानकारी दें ताकि प्रशासक आपको डॉक्टर नियुक्त कर सके। यह जानकारी निदान की पुष्टि नहीं करती।',
  'Please contact a qualified doctor for guidance before exercising. You can enter the app while we arrange your doctor assignment.': 'व्यायाम करने से पहले योग्य डॉक्टर से सलाह लें। डॉक्टर नियुक्त होने तक भी आप ऐप में जा सकते हैं।',
  'Yes, diagnosed': 'हाँ, डॉक्टर ने पुष्टि की है',
  'No diagnosis': 'निदान नहीं हुआ है',
  'Not sure': 'निश्चित नहीं',
  'Editing this occurrence. Changes apply only after saving.': 'इस सत्र में बदलाव कर रहे हैं। सहेजने के बाद ही बदलाव लागू होंगे।',
  'Schedule': 'समय-सारणी',
  'Start date and time (this device’s timezone)': 'शुरू होने की तारीख और समय (इस उपकरण का समय क्षेत्र)',
  'Number of days (1–366)': 'दिनों की संख्या (1–366)',
  'Patients are notified only when a session becomes available. An active or paused session is never overwritten.': 'सत्र उपलब्ध होने पर ही मरीज़ को सूचना मिलेगी। चालू या रोके हुए सत्र की जगह नया सत्र नहीं आएगा।',
  'Could not load schedule.': 'समय-सारणी नहीं मिली।',
  'Please enter a session name.': 'कृपया सत्र का नाम दर्ज करें।',
  'Select at least one exercise.': 'कम से कम एक व्यायाम चुनें।',
  'Doctor account not found. Please log in again.': 'डॉक्टर का खाता नहीं मिला। कृपया दोबारा लॉगिन करें।',
  'Exercise schedule saved.': 'व्यायाम की समय-सारणी सहेज ली गई है।',
  'Example: 10': 'उदाहरण: 10',
  'Contact admin': 'प्रशासक से संपर्क करें',
  'Search by patient ID': 'मरीज़ की पहचान से खोजें',
  'Ask an administrator to assign patients to your account.': 'प्रशासक से अपने खाते में मरीज़ नियुक्त करने को कहें।',
  'Session reports': 'सत्र की रिपोर्ट',
  'Progress analytics': 'प्रगति का विश्लेषण',
  'Session history': 'सत्र का इतिहास',
  'ASSIGNED EXERCISES': 'निर्धारित व्यायाम',
  'DURATION': 'अवधि',
  'AI': 'कृत्रिम बुद्धिमत्ता',
  'AI Confidence': 'AI का विश्वास स्तर',
  'Back to Dashboard': 'डैशबोर्ड पर वापस जाएँ',
  'Try Again': 'फिर प्रयास करें',
  'Unable to load session': 'सत्र नहीं मिल सका',
  'Physiotherapy Session': 'फिजियोथेरेपी सत्र',
  'Help': 'सहायता',
  'Please wait while we assign you a doctor. Exercise demonstrations are available below.': 'डॉक्टर नियुक्त होने तक कृपया प्रतीक्षा करें। नीचे व्यायाम का प्रदर्शन देख सकते हैं।',
  'Edit': 'बदलें',
  'Movement guide': 'व्यायाम मार्गदर्शन',
  'Pose landmarks detected by real-time MediaPipe model.': 'MediaPipe मॉडल से शरीर की मुद्रा के बिंदु पहचाने गए हैं।',
  'Doctor feedback': 'डॉक्टर की प्रतिक्रिया',
  'Could not load reports.': 'रिपोर्ट नहीं मिल सकीं।',
  'No session reports yet.': 'अभी कोई सत्र रिपोर्ट नहीं है।',
  'Not available': 'उपलब्ध नहीं',
  'Review these results with your doctor. Movement scores and camera-based angles are prototype estimates, not clinical measurements.': 'इन परिणामों पर अपने डॉक्टर से चर्चा करें। गतिविधि के स्कोर और कैमरे से निकले कोण प्रोटोटाइप के अनुमान हैं, चिकित्सकीय माप नहीं।',
  'Describe your concern': 'अपनी समस्या बताएँ',
  'Help messages are reviewed by administrators. For urgent medical concerns, contact your treating doctor or local emergency service.': 'सहायता संदेश प्रशासक देखते हैं। तत्काल चिकित्सा सहायता के लिए अपने चिकित्सक या स्थानीय आपातकालीन सेवा से संपर्क करें।',
  'Send a concern or message to the administrator and track replies here.': 'प्रशासक को अपनी समस्या या संदेश भेजें और उत्तर यहाँ देखें।',
  'Research and development consent': 'अनुसंधान और विकास की सहमति',
  'Optional. Change your choice at any time.': 'वैकल्पिक है। अपना निर्णय कभी भी बदलें।',
  'Could not load requests. Please try again.': 'अनुरोध नहीं मिले। कृपया फिर प्रयास करें।',
  'No requests yet.': 'अभी कोई अनुरोध नहीं है।',
  'Close request': 'अनुरोध बंद करें',
  'Message': 'संदेश',
  'Doctor not responding': 'डॉक्टर उत्तर नहीं दे रहे',
  'Doctor assignment': 'डॉक्टर नियुक्ति',
  'Technical problem': 'तकनीकी समस्या',
  'open': 'खुला',
  'closed': 'बंद',
  'Reply': 'उत्तर',
  'Once': 'एक बार',
  'One week': 'एक सप्ताह',
  'One month': 'एक महीना',
  'Custom days': 'अपनी दिन संख्या',
  'Mon': 'सोम',
  'Tue': 'मंगल',
  'Wed': 'बुध',
  'Thu': 'गुरु',
  'Fri': 'शुक्र',
  'Sat': 'शनि',
  'Sun': 'रवि',
  'Edit this session': 'यह सत्र बदलें',
  'Cancel this session': 'यह सत्र रद्द करें',
  'Cancel remaining series': 'श्रृंखला के बाकी सत्र रद्द करें',
  'Live sessions': 'चालू सत्र',
  'Add doctor': 'डॉक्टर जोड़ें',
  'Doctor account created. Share the login credentials securely with the doctor.': 'डॉक्टर का खाता बन गया। लॉगिन जानकारी सुरक्षित तरीके से डॉक्टर को दें।',
  'Initial password': 'शुरुआती पासवर्ड',
  'Registration number': 'पंजीकरण संख्या',
  'Hospital / clinic': 'अस्पताल / क्लिनिक',
  'Create doctor account': 'डॉक्टर का खाता बनाएँ',
  'The doctor must accept the terms on their first login.': 'डॉक्टर को पहले लॉगिन पर नियम स्वीकार करने होंगे।',
  'Required': 'अनिवार्य',
  'At least 8 characters': 'कम से कम 8 अक्षर',
  'View Error': 'त्रुटि देखें',
  'Error frame unavailable.': 'त्रुटि की छवि उपलब्ध नहीं है।',
  'Error image unavailable.': 'त्रुटि की छवि उपलब्ध नहीं है।',
  'WHERE THE FORM WENT WRONG': 'व्यायाम की मुद्रा कहाँ गलत हुई',
  'Reset Zoom': 'ज़ूम रीसेट करें',
  'Minimize': 'छोटा करें',
  'Pinch or drag to zoom and inspect form error': 'मुद्रा की त्रुटि देखने के लिए उँगलियों से ज़ूम या खींचें',
  'Maximize to Fullscreen': 'पूरी स्क्रीन में देखें',
  'Pinch to zoom • Tap maximize for fullscreen': 'उँगलियों से ज़ूम करें • पूरी स्क्रीन के लिए बड़ा करें',
  'End assessment?': 'मूल्यांकन समाप्त करें?',
  'No exercises assigned.': 'कोई व्यायाम निर्धारित नहीं है।',
  'correct reps': 'सही दोहराव',
  'e.g. Morning Upper Body Rehab': 'जैसे: सुबह का ऊपरी शरीर व्यायाम',

  // App Branding & Navigation
  'HaemoPhysio': 'HaemoPhysio',
  'Log out': 'लॉग आउट',
  'Edit Profile': 'प्रोफ़ाइल संपादित करें',
  'Account': 'खाता',
  'Back': 'वापस',
  'Save': 'सहेजें',
  'Cancel': 'रद्द करें',
  'Done': 'संपन्न',
  'Close': 'बंद करें',
  'Error': 'त्रुटि',
  'Loading...': 'लोड हो रहा है...',
  'Refresh': 'ताज़ा करें',
  'Continue': 'जारी रखें',
  'Submit': 'जमा करें',
  'Confirm': 'पुष्टि करें',
  'Details': 'विवरण',

  // Doctor Dashboard
  'Welcome, Dr.': 'स्वागत है, डॉ.',
  'Review patient progress, movement quality and clinical feedback.':
      'मरीज़ की प्रगति, गति की गुणवत्ता और नैदानिक फीडबैक की समीक्षा करें।',
  'Assigned Patients': 'असाइन किए गए मरीज़',
  'Your patients': 'आपके मरीज़',
  'Open a patient to review sessions and errors.':
      'सत्र और त्रुटियों की समीक्षा के लिए मरीज़ पर टैप करें।',
  'No patients assigned': 'कोई मरीज़ असाइन नहीं है',
  'You have not assigned exercises to any patients yet.':
      'आपने अभी तक किसी भी मरीज़ को व्यायाम असाइन नहीं किया है।',
  'Assign exercises to a patient': 'मरीज़ को व्यायाम असाइन करें',
  'Select Patient to Assign': 'व्यायाम असाइन करने के लिए मरीज़ चुनें',
  'No registered patients found.': 'कोई पंजीकृत मरीज़ नहीं मिला।',
  'Active Session': 'सक्रिय सत्र',
  'Paused Session': 'रोका गया सत्र',
  'Recently Completed Assessments': 'हाल ही में पूरे किए गए मूल्यांकन',
  'Review': 'समीक्षा',
  'View Patient': 'मरीज़ देखें',
  'Message patient': 'मरीज़ को संदेश भेजें',
  'Message Patient': 'मरीज़ को संदेश भेजें',
  'Assign Exercises': 'व्यायाम असाइन करें',
  'No assessments yet': 'अभी तक कोई मूल्यांकन नहीं',
  'No sessions recorded yet': 'अभी तक कोई सत्र दर्ज नहीं किया गया है',
  'Patient': 'मरीज़',
  'Accuracy': 'सटीकता',
  'Total Sessions': 'कुल सत्र',
  'Avg Score': 'औसत स्कोर',
  'Total Reps': 'कुल रेप्स',
  'Sessions': 'सत्र',
  'Average Score': 'औसत स्कोर',
  'reps': 'रेप्स',
  'reps completed': 'रेप्स पूरे हुए',
  'Completed': 'पूर्ण',
  'In Progress': 'प्रगति पर',
  'Paused': 'रोका हुआ',
  'Assigned': 'असाइन किया गया',
  'Discarded': 'अस्वीकृत',
  'Abandoned': 'अधूरा',
  'Pending': 'लंबित',
  'Current Program': 'वर्तमान कार्यक्रम',
  'Overall Progress': 'समग्र प्रगति',
  'Target': 'लक्ष्य',
  'Target Reps': 'लक्ष्य रेप्स',
  'Correct Reps': 'सही रेप्स',
  'Completed Reps': 'पूर्ण रेप्स',
  'Attempted': 'प्रयास किए गए',
  'Clinical Notes': 'नैदानिक टिप्पणियाँ',
  'Prescribed Exercises': 'निर्धारित व्यायाम',
  'Movement Quality': 'गति की गुणवत्ता',
  'Session History': 'सत्र इतिहास',
  'Doctor Messages': 'डॉक्टर संदेश',

  // Patient Dashboard
  'Welcome back,': 'वापसी पर स्वागत है,',
  'Track exercises, monitor progress and recover safely.':
      'व्यायाम ट्रैक करें, प्रगति देखें और सुरक्षित रूप से स्वस्थ हों।',
  'Daily Exercise Program': 'दैनिक व्यायाम कार्यक्रम',
  'Assigned by Dr.': 'डॉ. द्वारा असाइन किया गया',
  'Start Exercise Program': 'व्यायाम कार्यक्रम शुरू करें',
  'Resume Exercise Program': 'व्यायाम कार्यक्रम पुनः आरंभ करें',
  'Start Session': 'सत्र शुरू करें',
  'Resume Session': 'सत्र पुनः आरंभ करें',
  'Program Completed!': 'कार्यक्रम पूरा हुआ!',
  'Great job! You have completed today\'s assigned program.':
      'शाबाश! आपने आज का निर्धारित कार्यक्रम पूरा कर लिया है।',
  'No Active Assignment': 'कोई सक्रिय असाइनमेंट नहीं',
  'Your doctor has not assigned an exercise program yet.':
      'आपके डॉक्टर ने अभी तक कोई व्यायाम कार्यक्रम असाइन नहीं किया है।',
  'Quick Exercise': 'त्वरित व्यायाम',
  'Start any exercise independently': 'स्वतंत्र रूप से कोई भी व्यायाम शुरू करें',
  'Progress History': 'प्रगति का इतिहास',
  'View your completed sessions and stats': 'अपने पूर्ण सत्र और आंकड़े देखें',
  'Message Doctor': 'डॉक्टर को संदेश भेजें',
  'Consult with your assigned clinician': 'अपने नियुक्त डॉक्टर से परामर्श करें',
  'Start Assessment': 'मूल्यांकन शुरू करें',
  'Active Assignment': 'सक्रिय असाइनमेंट',
  'Session Progress': 'सत्र की प्रगति',
  'Save & Exit': 'सहेजें और बाहर निकलें',
  'Discard': 'हटाएं',
  'Discard Exercise': 'व्यायाम हटाएं',
  'Are you sure you want to discard this exercise?':
      'क्या आप वाकई इस व्यायाम को हटाना चाहते हैं?',
  'Only current unfinished progress will be reset. Previous completed exercises remain saved.':
      'केवल वर्तमान अधूरा कार्य रीसेट होगा। पहले पूरे किए गए व्यायाम सुरक्षित रहेंगे।',
  'Position your full body in the camera frame.':
      'अपने पूरे शरीर को कैमरा फ्रेम में रखें।',
  'Keep your device steady.': 'अपने डिवाइस को स्थिर रखें।',
  'Ready to begin?': 'शुरू करने के लिए तैयार?',
  'Live Feedback': 'लाइव फीडबैक',
  'Exercise Complete': 'व्यायाम संपन्न',
  'All Exercises Completed': 'सभी व्यायाम पूरे हो गए',
  'Assessment Completed': 'मूल्यांकन पूरा हुआ',
  'Great work!': 'बहुत बढ़िया!',
  'Score': 'स्कोर',
  'Summary': 'सारांश',
  'View Analytics': 'एनालिटिक्स देखें',
  'Return to Dashboard': 'डैशबोर्ड पर वापस जाएं',

  // Chat & Messaging
  'Type a message...': 'संदेश लिखें...',
  'Send': 'भेजें',
  'No messages yet': 'अभी तक कोई संदेश नहीं',
  'Start a conversation with your patient': 'अपने मरीज़ के साथ बातचीत शुरू करें',
  'Start a conversation with your doctor': 'अपने डॉक्टर के साथ बातचीत शुरू करें',

  // Session & Progress specifics
  'ASSESSMENT IN PROGRESS': 'मूल्यांकन प्रगति पर है',
  'Resume Assessment': 'मूल्यांकन पुनः आरंभ करें',
  'Discard Session?': 'सत्र हटाएं?',
  'Are you sure you want to discard your progress? This session cannot be resumed once discarded.':
      'क्या आप वाकई अपनी प्रगति हटाना चाहते हैं? हटाए जाने के बाद यह सत्र दोबारा शुरू नहीं किया जा सकता।',
  'All done for now': 'फिलहाल सब पूरा हो गया',
  'Your doctor will assign your next session when you are ready.':
      'तैयार होने पर आपके डॉक्टर आपका अगला सत्र असाइन करेंगे।',
  'No exercise session is currently assigned.':
      'वर्तमान में कोई व्यायाम सत्र असाइन नहीं किया गया है।',
  'Recent sessions': 'हाल के सत्र',
  'Detailed session summary and completion status':
      'विस्तृत सत्र सारांश और पूर्णता स्थिति',
  'View history': 'इतिहास देखें',
  'Doctor messages': 'डॉक्टर संदेश',
  'View guidance and message your doctor.':
      'मार्गदर्शन देखें और अपने डॉक्टर को संदेश भेजें।',
  'Active Live Assessments': 'सक्रिय लाइव मूल्यांकन',
  'Paused Assessments': 'रोके गए मूल्यांकन',
  'Could not load patients.': 'मरीज़ लोड नहीं किए जा सके।',
  'PAUSED': 'रोका हुआ',
  'IN PROGRESS': 'प्रगति पर',
  'Session': 'सत्र',
  'paused': 'रोका हुआ',
  'in progress': 'प्रगति पर',
  'complete': 'पूर्ण',
  'Latest session': 'नवीनतम सत्र',
  'Assign Exercises to Patient': 'मरीज़ को व्यायाम असाइन करें',
  'Exercise library & guides': 'व्यायाम लाइब्रेरी और मार्गदर्शिका',
  'Step-by-step technique guides and interactive demonstrations':
      'चरण-दर-चरण तकनीक गाइड और इंटरैक्टिव प्रदर्शन',
  'Tutorial': 'ट्यूटोरियल',
  'Practice': 'अभ्यास',
  'Clinically Validated': 'चिकित्सकीय रूप से मान्य',
  'No assessment sessions yet': 'अभी तक कोई मूल्यांकन सत्र नहीं',
  'Complete your first assessment to see your results here.':
      'अपने परिणाम यहाँ देखने के लिए अपना पहला मूल्यांकन पूरा करें।',
  'Your progress': 'आपकी प्रगति',
  'Clear summary of your physiotherapy performance':
      'आपके फिजियोथेरेपी प्रदर्शन का स्पष्ट सारांश',
  'Avg ROM': 'औसत ROM',
  'Most recent focus': 'हालिया फोकस',
  'Could not load assessments': 'मूल्यांकन लोड नहीं हो सके',

  // Auth - Login Screen
  'Physiotherapy Assistant': 'फिजियोथेरेपी सहायक',
  'Welcome back': 'वापसी पर स्वागत है',
  'Sign in to continue your physiotherapy journey.':
      'अपनी फिजियोथेरेपी यात्रा जारी रखने के लिए साइन इन करें।',
  'Email': 'ईमेल',
  'Password': 'पासवर्ड',
  'Show password': 'पासवर्ड दिखाएं',
  'Hide password': 'पासवर्ड छुपाएं',
  'Sign in': 'साइन इन',
  "Don't have an account?": 'खाता नहीं है?',
  'Create one': 'बनाएं',
  'Secure account authentication': 'सुरक्षित खाता प्रमाणीकरण',
  'Please enter your email.': 'कृपया अपना ईमेल दर्ज करें।',
  'Please enter your password.': 'कृपया अपना पासवर्ड दर्ज करें।',
  'Invalid email or password.': 'अमान्य ईमेल या पासवर्ड।',
  'No account exists with this email.': 'इस ईमेल से कोई खाता मौजूद नहीं है।',
  'Incorrect password.': 'गलत पासवर्ड।',
  'Please enter a valid email address.': 'कृपया एक मान्य ईमेल पता दर्ज करें।',
  'This account has been disabled.': 'यह खाता अक्षम कर दिया गया है।',
  'Too many attempts. Please try again later.':
      'बहुत अधिक प्रयास। कृपया बाद में पुनः प्रयास करें।',
  'Login failed. Please try again.': 'लॉगिन विफल। कृपया पुनः प्रयास करें।',

  // Auth - Register Screen
  'HaemoPhysio Registration': 'HaemoPhysio पंजीकरण',
  'Create your account': 'अपना खाता बनाएं',
  'Register your HaemoPhysio patient profile.':
      'अपनी HaemoPhysio मरीज़ प्रोफ़ाइल पंजीकृत करें।',
  'Full Name': 'पूरा नाम',
  'Full Name *': 'पूरा नाम *',
  'Create patient account': 'मरीज़ खाता बनाएं',
  'Already have an account? Sign in': 'पहले से खाता है? साइन इन करें',
  'Patient account created successfully.': 'मरीज़ खाता सफलतापूर्वक बनाया गया।',
  'Please fill in all fields.': 'कृपया सभी फ़ील्ड भरें।',
  'Please enter your full name.': 'कृपया अपना पूरा नाम दर्ज करें।',
  'Password must contain at least 6 characters.':
      'पासवर्ड में कम से कम 6 अक्षर होने चाहिए।',
  'An account already exists with this email.':
      'इस ईमेल से पहले से एक खाता मौजूद है।',
  'Please choose a stronger password.': 'कृपया एक मज़बूत पासवर्ड चुनें।',
  'Registration failed.': 'पंजीकरण विफल।',
  'At least 6 characters': 'कम से कम 6 अक्षर',

  // Profile Screen
  'Doctor': 'डॉक्टर',
  'Admin': 'एडमिन',
  'Email Address': 'ईमेल पता',
  'Managed by Authentication and cannot be changed directly.':
      'प्रमाणीकरण द्वारा प्रबंधित। सीधे बदला नहीं जा सकता।',
  'Age': 'आयु',
  'Gender': 'लिंग',
  'Select gender': 'लिंग चुनें',
  'Male': 'पुरुष',
  'Female': 'महिला',
  'Other': 'अन्य',
  'Prefer not to say': 'बताना नहीं चाहते',
  'Phone Number': 'फ़ोन नंबर',
  'Save Changes': 'बदलाव सहेजें',
  'Saving...': 'सहेज रहे हैं...',
  'Profile updated successfully!': 'प्रोफ़ाइल सफलतापूर्वक अपडेट हुई!',
  'Could not update profile:': 'प्रोफ़ाइल अपडेट नहीं हो सकी:',
  'Please enter your full name': 'कृपया अपना पूरा नाम दर्ज करें',
  'Name must be at least 2 characters': 'नाम कम से कम 2 अक्षरों का होना चाहिए',
  'Please enter a valid whole number': 'कृपया एक मान्य पूर्ण संख्या दर्ज करें',
  'Age must be greater than 0': 'आयु 0 से अधिक होनी चाहिए',
  'Please enter a sensible age (up to 120)': 'कृपया एक उचित आयु दर्ज करें (120 तक)',

  // Admin Dashboard
  'Admin Dashboard': 'एडमिन डैशबोर्ड',
  'Total Users': 'कुल उपयोगकर्ता',
  'Doctors': 'डॉक्टर',
  'Patients': 'मरीज़',
  'Manage Users': 'उपयोगकर्ता प्रबंधित करें',
  'Role': 'भूमिका',
  'Name': 'नाम',
  'No users found': 'कोई उपयोगकर्ता नहीं मिला',
  'Search users...': 'उपयोगकर्ता खोजें...',
  'Delete': 'हटाएं',
  'Are you sure?': 'क्या आप सुनिश्चित हैं?',

  // Doctor Patient Detail
  'Patient Details': 'मरीज़ विवरण',
  'Exercises': 'व्यायाम',
  'No exercises assigned': 'कोई व्यायाम असाइन नहीं',
  'Assessment History': 'मूल्यांकन इतिहास',
  'No assessments found': 'कोई मूल्यांकन नहीं मिला',
  'View Details': 'विवरण देखें',
  'Date': 'तारीख',
  'Duration': 'अवधि',
  'Status': 'स्थिति',

  // Doctor Messages
  'Messages': 'संदेश',
  'Select a patient': 'एक मरीज़ चुनें',
  'No conversations yet': 'अभी तक कोई बातचीत नहीं',

  // Doctor Session Detail
  'Session Details': 'सत्र विवरण',
  'Exercise': 'व्यायाम',
  'Rep': 'रेप',
  'Feedback': 'फीडबैक',
  'No feedback': 'कोई फीडबैक नहीं',

  // Patient History
  'History': 'इतिहास',
  'No sessions found': 'कोई सत्र नहीं मिला',
  'Complete your first exercise to see history here.':
      'इतिहास देखने के लिए अपना पहला व्यायाम पूरा करें।',

  // Patient Messages
  'Chat with Doctor': 'डॉक्टर से चैट करें',
  'Your Doctor': 'आपके डॉक्टर',
  'No doctor assigned': 'कोई डॉक्टर असाइन नहीं',

  // Assessment Screens
  'Assessment': 'मूल्यांकन',
  'Preparing...': 'तैयारी हो रही है...',
  'Connecting...': 'कनेक्ट हो रहा है...',
  'Camera not available': 'कैमरा उपलब्ध नहीं',
  'Next Exercise': 'अगला व्यायाम',
  'Finish': 'समाप्त',
  'Well done!': 'बहुत बढ़िया!',
  'Try again': 'पुनः प्रयास करें',
  'Skip': 'छोड़ें',

  // Assigned Assessment
  'Assigned Exercises': 'असाइन किए गए व्यायाम',
  'No exercises have been assigned yet.':
      'अभी तक कोई व्यायाम असाइन नहीं किया गया है।',
  'Begin Assessment': 'मूल्यांकन शुरू करें',
  'exercises': 'व्यायाम',
  'target reps': 'लक्ष्य रेप्स',

  // Assign Exercises Screen
  'Save Assignment': 'असाइनमेंट सहेजें',
  'Session details': 'सत्र विवरण',
  'Session Name': 'सत्र का नाम',
  'Exercise plan': 'व्यायाम योजना',
  'Target correct reps': 'लक्ष्य सही रेप्स',
  'Assign exercises for': 'व्यायाम असाइन करें',
  'Give this physiotherapy session a name before assigning exercises.':
      'व्यायाम असाइन करने से पहले इस सत्र को एक नाम दें।',
  'Select the exercises and set the number of correct repetitions required.':
      'व्यायाम चुनें और आवश्यक सही दोहराव (रेप्स) की संख्या निर्धारित करें।',

  // Live Assessment Controls & Dialogs
  'LIVE ASSESSMENT': 'लाइव मूल्यांकन',
  'Discard Progress': 'प्रगति हटाएं',
  'Continue Assessment': 'मूल्यांकन जारी रखें',
  'Assessment in progress': 'मूल्यांकन प्रगति पर है',
  'You have not completed all exercises. What would you like to do?':
      'आपने सभी व्यायाम पूरे नहीं किए हैं। आप क्या करना चाहेंगे?',
  'How to perform': 'व्यायाम कैसे करें',
  'Expand UI': 'UI विस्तृत करें',
  'Compact UI': 'UI संक्षिप्त करें',
  'End': 'समाप्त',
  'End Assessment': 'मूल्यांकन समाप्त करें',
  'Session Completed!': 'सत्र संपन्न हुआ!',
  'Great job! You have completed all exercises for this session. Your progress has been saved.':
      'शाबाश! आपने इस सत्र के सभी व्यायाम पूरे कर लिए हैं। आपकी प्रगति सहेज ली गई है।',
  'Live Assessment Error': 'लाइव मूल्यांकन त्रुटि',
  'Go Back': 'वापस जाएं',
  'SCORE': 'स्कोर',
  'ROM': 'ROM',
  'SPEED': 'गति',
  'DUR': 'अवधि',
  'LSTM': 'मॉडल',
  'FORM': 'फॉर्म',
  'REP': 'रेप',
  'Correct': 'सही',
  'Incorrect': 'गलत',
  'correct': 'सही',
  'incorrect': 'गलत',
  'Waiting': 'प्रतीक्षा',
  'Good': 'अच्छा',
  'Slow': 'धीमा',
  'Fast': 'तेज',
  'this session': 'यह सत्र',

  // Exercise Demo Controls & Dialogs
  'Key Guidance for Safe Performance': 'सुरक्षित व्यायाम के लिए मुख्य मार्गदर्शन',
  'How to perform this exercise': 'इस व्यायाम को कैसे करें',
  'Got it, Continue': 'समझ गए, जारी रखें',
  'Step': 'चरण',
  'Pause': 'रोकें',
  'Play': 'चलाएं',
  'Replay from start': 'शुरू से पुनः चलाएं',
  'Auto-looping': 'ऑटो-लूपिंग',

  // Doctor Patient Detail & Sessions
  'Total Reps Attempted': 'कुल प्रयास किए गए रेप्स',
  'CURRENT ASSIGNMENT': 'वर्तमान असाइनमेंट',
  'Current': 'वर्तमान',
  'of': 'में से',
  'exercises finished': 'व्यायाम समाप्त',
  'Last activity': 'पिछली गतिविधि',
  'Patient Progress': 'मरीज़ की प्रगति',
  'Assessment score across completed sessions': 'पूर्ण सत्रों में मूल्यांकन स्कोर',
  'No progress data yet': 'अभी तक कोई प्रगति डेटा नहीं',
  'Session review': 'सत्र समीक्षा',
  'Average score': 'औसत स्कोर',
  'Correct reps': 'सही रेप्स',
  'Success rate': 'सफलता दर',
  'Average ROM': 'औसत ROM',
  'Avg duration': 'औसत अवधि',
  'AI confidence': 'AI विश्वास',
  'Message Patient About This Session': 'इस सत्र के बारे में मरीज़ को संदेश भेजें',
  'Rep-by-rep review': 'रेप-दर-रेप समीक्षा',

  // Messages & Threads
  'Private Consultation Thread': 'निजी परामर्श बातचीत',
  'No conversation yet': 'अभी तक कोई बातचीत नहीं',
  'Messages here are private between you and': 'यहाँ के संदेश आपके और इनके बीच निजी हैं:',
  'Discussing Session': 'सत्र पर चर्चा',
  'Write to': 'संदेश लिखें',
  'Tap to inspect ›': 'जांचने के लिए टैप करें ›',
  'Physician': 'चिकित्सक',
  'Send a message to': 'संदेश भेजें',
  'to start the conversation': 'बातचीत शुरू करने के लिए',
  'View Session ›': 'सत्र देखें ›',
  'No doctors available': 'कोई डॉक्टर उपलब्ध नहीं',
  'No messages yet • Tap to start chat': 'अभी तक कोई संदेश नहीं • चैट शुरू करने के लिए टैप करें',
  'ASSIGNED': 'असाइन किया गया',
  'Your clinician team will appear here once registered.':
      'पंजीकरण के बाद आपकी क्लिनिकल टीम यहाँ दिखाई देगी।',

  // Assigned Assessment specifics
  'Assigned Assessment': 'असाइन किया गया मूल्यांकन',
  'Assigned Session': 'असाइन किया गया सत्र',
  'Work in progress': 'प्रगति पर है',
  'Continue Session': 'सत्र जारी रखें',
  'Discard Session': 'सत्र हटाएं',
  'Are you sure you want to discard your progress? This session will be marked as discarded and cannot be resumed.':
      'क्या आप वाकई अपनी प्रगति हटाना चाहते हैं? इस सत्र को हटाया हुआ चिह्नित किया जाएगा और इसे पुनः आरंभ नहीं किया जा सकता है।',
  'SESSION NAME': 'सत्र का नाम',
  'Complete each exercise in the assigned order. Only correct repetitions count.':
      'प्रत्येक व्यायाम को निर्धारित क्रम में पूरा करें। केवल सही दोहराव ही गिने जाएंगे।',

  // Patient History & Charts
  'Assessments in this session': 'इस सत्र में मूल्यांकन',
  'Session Progress Trends': 'सत्र प्रगति रुझान',
  'Session-level averages across completed sessions': 'पूर्ण सत्रों में सत्र-स्तरीय औसत',
  'Complete assessment sessions to view progress trends.':
      'प्रगति रुझान देखने के लिए मूल्यांकन सत्र पूरे करें।',
  'Movement Score': 'गति स्कोर',
  'Average Movement Score': 'औसत गति स्कोर',
  'Range of Motion': 'गति की सीमा (ROM)',
  'Average Range of Motion': 'औसत गति की सीमा (ROM)',
  'Correct Rep Rate': 'सही रेप दर',
  'Average Duration': 'औसत अवधि',
  'Average AI Confidence': 'औसत AI विश्वास',
  'Tap any session data point to inspect details': 'विवरण जांचने के लिए किसी भी सत्र डेटा बिंदु पर टैप करें',
  'Latest Session': 'नवीनतम सत्र',
  'Overall Average': 'समग्र औसत',
  'Today': 'आज',
  'Needs Adjustment': 'सुधार की आवश्यकता',
  'Good Form': 'अच्छा फॉर्म',
  'RANGE OF MOTION': 'गति की सीमा (ROM)',
  'CORRECT REPS': 'सही रेप्स',
  'AVG SCORE': 'औसत स्कोर',
  'Technical Details': 'तकनीकी विवरण',
  'Focus': 'ध्यान दें',
  'Total Correct Reps': 'कुल सही रेप्स',
  'Completed (Needs Practice)': 'पूर्ण (अभ्यास आवश्यक)',
  'EXERCISES': 'व्यायाम',
  'AI Pose Confidence': 'AI मुद्रा विश्वास',

  // Exercise names & validation
  'Assisted Shoulder Flexion with Bar': 'बार के साथ सहायक शोल्डर फ्लेक्सन',
  'Shoulder Rotation': 'कंधे का घुमाव',
  'Assisted Elbow Flexion': 'सहायक कोहनी फ्लेक्सन',
  'Elbow Flexion & Extension': 'कोहनी फ्लेक्सन और विस्तार',
  'WORK IN PROGRESS': 'प्रगति पर है',
  'Only correct repetitions will count toward this target.':
      'केवल सही दोहराव ही इस लक्ष्य में गिने जाएंगे।',
  'Exercises assigned successfully.': 'व्यायाम सफलतापूर्वक असाइन किए गए।',

  // Somaiya HemoPhysio Branding & Mobile Auth
  'Somaiya HemoPhysio': 'Somaiya HemoPhysio',
  'Patient Login': 'रोगी लॉगिन',
  'Smart Physiotherapy Assistant': 'स्मार्ट फिजियोथेरेपी सहायक',
  'Physiotherapist Login': 'फिजियोथेरेपिस्ट लॉगिन',
  'Physiotherapist ID': 'फिजियोथेरेपिस्ट आईडी',
  'Physiotherapist ID / Email': 'फिजियोथेरेपिस्ट आईडी / ईमेल',
  'Please enter your email address.': 'कृपया अपना ईमेल पता दर्ज करें।',
  'Please enter your Physiotherapist ID or Email.':
      'कृपया अपनी फिजियोथेरेपिस्ट आईडी या ईमेल दर्ज करें।',
  'Sign in to continue your physiotherapy journey and track rehabilitation.':
      'अपनी फिजियोथेरेपी यात्रा जारी रखने और पुनर्वास ट्रैक करने के लिए साइन इन करें।',
  'Sign in to prescribe exercises, track patient recovery, and review AI assessments.':
      'व्यायाम निर्धारित करने, मरीज़ के सुधार को ट्रैक करने और AI मूल्यांकन की समीक्षा करने के लिए साइन इन करें।',
  'Forgot Password?': 'पासवर्ड भूल गए?',
  'Reset Password': 'पासवर्ड रीसेट करें',
  'Enter your registered email address to receive password reset instructions.':
      'पासवर्ड रीसेट निर्देश प्राप्त करने के लिए अपना पंजीकृत ईमेल पता दर्ज करें।',
  'Send Reset Link': 'रीसेट लिंक भेजें',
  'Password reset link sent to your email.':
      'आपकी ईमेल पर पासवर्ड रीसेट लिंक भेज दिया गया है।',
  'Could not send reset email:': 'रीसेट ईमेल भेजा नहीं जा सका:',
  'Sign In': 'साइन इन करें',
  'OR': 'या',
  'Continue with Google': 'Google के साथ जारी रखें',
  'Google Sign-In is not available on this device.':
      'इस डिवाइस पर Google साइन-इन उपलब्ध नहीं है।',
  'Register for an Account': 'खाता पंजीकृत करें',
  'Are you a Doctor / Physiotherapist?':
      'क्या आप डॉक्टर या फिजियोथेरेपिस्ट हैं?',
  'Physiotherapist Login ›': 'फिजियोथेरेपिस्ट लॉगिन ›',
  'Back to Patient Login': 'रोगी लॉगिन पर वापस जाएं',
  'Clinician & Healthcare Portal': 'चिकित्सक और स्वास्थ्य पोर्टल',
  'This account is registered as a patient. Please use the Patient Login.':
      'यह खाता एक मरीज़ के रूप में पंजीकृत है। कृपया रोगी लॉगिन का उपयोग करें।',
  'This account is registered as a doctor. Please use the Physiotherapist Login.':
      'यह खाता डॉक्टर के रूप में पंजीकृत है। कृपया फिजियोथेरेपिस्ट लॉगिन का उपयोग करें।',

  // Patient Registration
  'Patient Registration': 'रोगी पंजीकरण',
  'Create your patient profile to begin your guided physiotherapy.':
      'अपनी निर्देशित फिजियोथेरेपी शुरू करने के लिए अपनी मरीज़ प्रोफ़ाइल बनाएं।',
  'Create Patient Account': 'रोगी खाता बनाएं',
  'First Name': 'पहला नाम',
  'Middle Name': 'मध्य नाम',
  'Last Name': 'अंतिम नाम',
  'Optional': 'वैकल्पिक',
  'Confirm Password': 'पासवर्ड की पुष्टि करें',
  'Passwords do not match.': 'पासवर्ड मेल नहीं खाते।',
  'Please enter your first name.': 'कृपया अपना पहला नाम दर्ज करें।',
  'Please enter your last name.': 'कृपया अपना अंतिम नाम दर्ज करें।',
  'Mobile Number': 'मोबाइल नंबर',
  'Please enter your mobile phone number.':
      'कृपया अपना मोबाइल फ़ोन नंबर दर्ज करें।',

  // Doctor Registration & Approval
  'Doctor Registration': 'डॉक्टर पंजीकरण',
  'Clinician Credential Registration': 'चिकित्सक क्रेडेंशियल पंजीकरण',
  'Personal Information': 'व्यक्तिगत जानकारी',
  'Provide your legal contact and identity details.':
      'अपने कानूनी संपर्क और पहचान विवरण प्रदान करें।',
  'City': 'शहर',
  'Please enter your city.': 'कृपया अपना शहर दर्ज करें।',
  'State / Province': 'राज्य',
  'Country': 'देश',
  'Account Password': 'खाता पासवर्ड',
  'Professional Information': 'व्यावसायिक जानकारी',
  'Enter your medical council registration and practice details.':
      'अपनी मेडिकल काउंसिल पंजीकरण और अभ्यास विवरण दर्ज करें।',
  'Medical Registration Number': 'चिकित्सा पंजीकरण संख्या',
  'Please enter your medical registration number.':
      'कृपया अपनी चिकित्सा पंजीकरण संख्या दर्ज करें।',
  'Medical Council / Regulatory Authority':
      'चिकित्सा परिषद / नियामक प्राधिकरण',
  'Please specify your medical council or regulatory authority.':
      'कृपया अपनी चिकित्सा परिषद या नियामक प्राधिकरण निर्दिष्ट करें।',
  'Medical Qualification': 'चिकित्सा योग्यता',
  'Please enter your medical qualification (e.g. BPT, MPT).':
      'कृपया अपनी चिकित्सा योग्यता (उदा. BPT, MPT) दर्ज करें।',
  'Medical Specialization': 'चिकित्सा विशेषज्ञता',
  'Hospital / Organization': 'अस्पताल / संगठन',
  'Please enter your hospital or affiliated organization.':
      'कृपया अपना अस्पताल या संबद्ध संगठन दर्ज करें।',
  'Years of Experience': 'अनुभव के वर्ष',
  'Professional Documents': 'व्यावसायिक दस्तावेज़',
  'Upload clear scans or photos of your credentials (PDF, JPG, PNG). Max 10MB.':
      'अपने क्रेडेंशियल (PDF, JPG, PNG) के स्पष्ट स्कैन या फ़ोटो अपलोड करें। अधिकतम 10MB।',
  'Medical Registration Certificate': 'चिकित्सा पंजीकरण प्रमाणपत्र',
  'Professional ID Document': 'व्यावसायिक पहचान पत्र',
  'Please attach your medical registration certificate or ID document.':
      'कृपया अपना चिकित्सा पंजीकरण प्रमाणपत्र या पहचान पत्र संलग्न करें।',
  'Upload Document': 'दस्तावेज़ अपलोड करें',
  'Remove': 'हटाएं',
  'Error selecting file:': 'फ़ाइल चुनने में त्रुटि:',
  'Verification & Approval': 'सत्यापन और अनुमोदन',
  'All doctor and physiotherapist accounts require credential verification by an administrator before clinical dashboard access is granted. You will be notified once your registration is approved.':
      'क्लिनिकल डैशबोर्ड एक्सेस दिए जाने से पहले सभी डॉक्टर और फिजियोथेरेपिस्ट खातों के लिए व्यवस्थापक द्वारा क्रेडेंशियल सत्यापन आवश्यक है। आपका पंजीकरण स्वीकृत होने पर आपको सूचित किया जाएगा।',
  'Registration Summary': 'पंजीकरण सारांश',
  'Name:': 'नाम:',
  'Registration No:': 'पंजीकरण संख्या:',
  'Council:': 'परिषद:',
  'Hospital:': 'अस्पताल:',
  'Documents:': 'दस्तावेज़:',
  'I hereby declare that all information and uploaded documents provided are authentic, accurate, and valid under medical regulatory authority guidelines.':
      'मैं एतद्द्वारा घोषित करता/करती हूँ कि प्रदान की गई सभी जानकारी और अपलोड किए गए दस्तावेज़ प्रामाणिक, सटीक और मान्य हैं।',
  'Please accept the declaration before submitting your registration.':
      'पंजीकरण जमा करने से पहले कृपया घोषणा स्वीकार करें।',
  'Submit Registration': 'पंजीकरण जमा करें',
  'Personal': 'व्यक्तिगत',
  'Professional': 'व्यावसायिक',
  'Documents': 'दस्तावेज़',
  'Declaration': 'घोषणा',
  'Previous': 'पिछला',
  'Next': 'आगे',
  'New clinician?': 'नए चिकित्सक?',
  'Already have a clinician account?': 'क्या आपके पास पहले से चिकित्सक खाता है?',
  'Already have a clinician account? Sign in':
      'क्या आपके पास पहले से चिकित्सक खाता है? साइन इन करें',

  // Pending Approval Screen
  'Clinician Portal': 'चिकित्सक पोर्टल',
  'Application Under Review': 'आवेदन समीक्षाधीन है',
  'Credentials Verification Pending': 'क्रेडेंशियल सत्यापन लंबित है',
  'Thank you for registering, Dr. {name}. Your professional credentials and medical council registration are currently being verified by the Somaiya clinical administration team. You will receive access as soon as your account is approved.':
      'पंजीकरण के लिए धन्यवाद, डॉ. {name}। आपके क्रेडेंशियल और पंजीकरण की वर्तमान में सोमैया क्लिनिकल टीम द्वारा समीक्षा की जा रही है। अनुमोदन के बाद आपको एक्सेस मिल जाएगा।',
  'Doctor Name': 'डॉक्टर का नाम',
  'Checking Status...': 'स्थिति जांची जा रही है...',
  'Check Approval Status': 'स्वीकृति स्थिति जांचें',
  'Your registration is still under review by the clinical administration team.':
      'आपका पंजीकरण अभी भी क्लिनिकल प्रशासन टीम द्वारा समीक्षाधीन है।',
  'Error checking status:': 'स्थिति जांचने में त्रुटि:',
  'Sign Out': 'साइन आउट करें',

  // --------------------------------------------------
  // PART 1A: EXERCISE CARDS
  // --------------------------------------------------
  'Two-handed bar elevation exercise targeting shoulder mobility and joint preservation.':
      'कंधे की गतिशीलता और जोड़ों की सुरक्षा के लिए दोनों हाथों से बार उठाने का व्यायाम।',
  'Bilateral internal and external rotation with elbows flexed 90° pinned to torso.':
      'धड़ से सटी 90° मुड़ी हुई कोहनियों के साथ दोनों तरफ आंतरिक और बाहरी घुमाव।',
  'Supported elbow bending using contralateral hand guidance to protect recovering joints.':
      'स्वस्थ हो रहे जोड़ों की सुरक्षा के लिए दूसरे हाथ के सहारे कोहनी मोड़ना।',
  'Smooth, controlled elbow bending and extension throughout comfortable pain-free range.':
      'दर्द रहित आरामदायक सीमा में नियंत्रित रूप से कोहनी मोड़ना और सीधा करना।',
  'Shoulder Flexion': 'कंधे का मोड़',
  'Assisted Elbow': 'सहायता प्राप्त कोहनी',
  'Elbow Flex / Ext': 'कोहनी मोड़ना / सीधा करना',
  'Shoulders': 'कंधे',
  'Rotator Cuff': 'रोटर कफ',
  'Elbow Joint': 'कोहनी का जोड़',
  'Work in Progress': 'प्रगति पर है',
  'Needs Practice': 'अभ्यास की आवश्यकता',

  // --------------------------------------------------
  // PART 1B: MOST RECENT FOCUS
  // --------------------------------------------------
  'Most Recent Focus': 'हाल का मुख्य ध्यान',
  'Keep both arms level during the movement.':
      'गति के दौरान दोनों हाथों को एक समान स्तर पर रखें।',
  'Raise both arms at an even height and symmetric speed.':
      'दोनों हाथों को समान ऊँचाई और समान गति से उठाएँ।',
  'Raise both arms at an even height and symmetrical speed.':
      'दोनों हाथों को समान ऊँचाई और समान गति से उठाएँ।',
  'Keep your torso upright and avoid leaning sideways.':
      'अपने धड़ को सीधा रखें और बगल में झुकने से बचें।',
  'Focus on controlled, steady movement through the full range of motion.':
      'पूरी गति सीमा में नियंत्रित और स्थिर गति पर ध्यान केंद्रित करें।',
  'Rep completed.': 'रेप पूर्ण हुआ।',

  // --------------------------------------------------
  // PART 1C: HISTORY & SESSIONS
  // --------------------------------------------------
  'View History': 'इतिहास देखें',
  'Recent Sessions': 'हाल के सत्र',
  'Completed Sessions': 'पूर्ण सत्र',
  'Loading your assessments...': 'आपके मूल्यांकन लोड हो रहे हैं...',

  // --------------------------------------------------
  // PART 2: HEALTH SCREENING CHATBOT & WIDGET
  // --------------------------------------------------
  'Health Risk Screening': 'स्वास्थ्य जोखिम जाँच',
  'Check your symptoms and understand possible health risks.':
      'अपने लक्षणों की जाँच करें और संभावित स्वास्थ्य जोखिमों को समझें।',
  'Start Screening': 'जाँच शुरू करें',
  'Start': 'शुरू करें',
  'This screening is informational and does not replace a medical diagnosis.':
      'यह जाँच केवल जानकारी के लिए है और चिकित्सकीय निदान का विकल्प नहीं है।',
  'Health Screening': 'स्वास्थ्य जाँच',
  'Hemophilia Health Risk Screening': 'हीमोफीलिया स्वास्थ्य जोखिम जाँच',
  'Screening Guidance': 'जाँच मार्गदर्शन',
  'Screening Result': 'जाँच परिणाम',
  'Risk Category': 'जोखिम श्रेणी',
  'Screening Confidence': 'जाँच विश्वास',
  'Based on your reported symptoms and health history, the automated screening model produced the following result:':
      'आपके द्वारा बताए गए लक्षणों और स्वास्थ्य इतिहास के आधार पर, स्वचालित जाँच मॉडल ने निम्नलिखित परिणाम दिया है:',
  'Healthy': 'स्वस्थ',
  'Mild': 'हल्का जोखिम',
  'Moderate': 'मध्यम जोखिम',
  'Severe': 'गंभीर जोखिम',
  'Low Risk': 'कम जोखिम',
  'Moderate Risk': 'मध्यम जोखिम',
  'High Risk': 'उच्च जोखिम',
  'Unknown': 'अज्ञात',
  'Restart Screening': 'पुनः जाँच करें',
  'Step {current} of {total}': 'चरण {current} का {total}',
  'Your Age (years)': 'आपकी आयु (वर्ष)',
  'Your Biological Sex': 'आपका जैविक लिंग',
  'Do you bleed longer than others after minor cuts?':
      'क्या छोटे कट लगने पर आपको दूसरों की तुलना में अधिक समय तक रक्तस्राव होता है?',
  'Have you experienced excessive bleeding after surgery or stitches?':
      'क्या आपको सर्जरी या टांके लगने के बाद अत्यधिक रक्तस्राव हुआ है?',
  'Have you experienced excessive bleeding after dental procedures?':
      'क्या आपको दंत चिकित्सा प्रक्रियाओं के बाद अत्यधिक रक्तस्राव का अनुभव हुआ है?',
  'Do you develop large or unusual bruises easily?':
      'क्या आपको आसानी से बड़े या असामान्य नील पड़ जाते हैं?',
  'Have you experienced unexplained deep muscle swelling, pain, or tenderness?':
      'क्या आपने बिना किसी बड़ी चोट के मांसपेशियों में सूजन, दर्द या कोमलता महसूस की है?',
  'Have you experienced repeated joint swelling or bleeding episodes without major injury?':
      'क्या आपको बिना किसी बड़ी चोट के जोड़ों में बार-बार सूजन या रक्तस्राव हुआ है?',
  'During joint episodes, have you noticed warmth around the affected joint?':
      'जोड़ों की समस्या के दौरान, क्या आपने प्रभावित जोड़ के आसपास गर्माहट महसूस की है?',
  'During joint episodes, have you noticed tightness or stiffness in the joint?':
      'जोड़ों की समस्या के दौरान, क्या आपने जोड़ में जकड़न महसूस की है?',
  'Have you experienced reduced mobility or difficulty moving the affected joint?':
      'क्या आपको प्रभावित जोड़ को हिलाने-डुलाने में कठिनाई या गतिशीलता में कमी महसूस हुई है?',
  'Have you noticed blood in your urine (hematuria)?':
      'क्या आपने अपने मूत्र में रक्त (हेमट्यूरिया) देखा है?',
  'Have you noticed blood in your stool (hematochezia)?':
      'क्या आपने अपने मल में रक्त देखा है?',
  'Is there a known family history of hemophilia or bleeding disorders?':
      'क्या आपके परिवार में हीमोफीलिया या रक्तस्राव विकारों का कोई इतिहास है?',
  'Do you have any male relatives diagnosed with hemophilia?':
      'क्या आपके किसी पुरुष रिश्तेदार को हीमोफीलिया का निदान हुआ है?',
  'Have you ever had a previous clotting factor deficiency test?':
      'क्या आपने कभी पहले क्लॉटिंग फैक्टर की जाँच कराई है?',
  'Never': 'कभी नहीं',
  'Sometimes': 'कभी-कभी',
  'Often': 'अक्सर',
  'Yes': 'हाँ',
  'No': 'नहीं',
  'Please answer the question above before proceeding.':
      'कृपया आगे बढ़ने से पहले ऊपर दिए गए प्रश्न का उत्तर दें।',
  'Analyzing your responses with the clinical screening model...':
      'क्लिनिकल जाँच मॉडल के साथ आपकी प्रतिक्रियाओं का विश्लेषण किया जा रहा है...',
  'Unable to complete screening. Please check your connection and try again.':
      'जाँच पूरी करने में असमर्थ। कृपया अपना कनेक्शन जांचें और पुनः प्रयास करें।',
  'Summary of Considered Symptoms': 'विचार किए गए लक्षणों का सारांश',
  'Medical Consultation Recommended': 'चिकित्सीय परामर्श की सलाह',
  'If you experience persistent, spontaneous, or severe bleeding, please consult a qualified hematologist or physician promptly.':
      'यदि आपको लगातार, स्वतः या गंभीर रक्तस्राव का अनुभव होता है, तो कृपया तुरंत किसी योग्य हेमेटोलॉजिस्ट या चिकित्सक से परामर्श लें।',
};

final Map<String, String> _normalizedHindiTranslations = {
  for (final entry in _hindiTranslations.entries) entry.key.toLowerCase().trim(): entry.value,
};
