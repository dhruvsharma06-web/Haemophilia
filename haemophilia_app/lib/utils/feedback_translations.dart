/// Hindi copy for the October 2026 review fixes: password policy, single-device
/// sign-in, grievance resolution, reminders, tutorials, calibration and
/// exercise snapshots.
const feedbackHindi = <String, String>{
  // Password policy
  'At least 8 characters with a letter and a number. Avoid sequences like "abc" or "123".':
      'कम से कम 8 अक्षर, जिनमें एक अक्षर और एक अंक हो। "abc" या "123" जैसे क्रम न रखें।',
  'Use no more than 128 characters.': '128 से अधिक अक्षर न रखें।',
  'Do not repeat the same character three or more times in a row.':
      'एक ही अक्षर को लगातार तीन या अधिक बार न दोहराएँ।',
  'Avoid consecutive sequences such as "abc", "123", "cba" or "qwer".':
      '"abc", "123", "cba" या "qwer" जैसे लगातार क्रम न रखें।',
  'Avoid common words such as "password" or the app name.':
      '"password" जैसे आम शब्द या ऐप का नाम न रखें।',
  'Do not include your name or email address in the password.':
      'पासवर्ड में अपना नाम या ईमेल पता न रखें।',

  // Sign-in
  'Invalid email or password.': 'ईमेल या पासवर्ड गलत है।',
  'Invalid email or password for this sign-in page. Patients and physiotherapists sign in on separate pages.':
      'इस साइन-इन पेज के लिए ईमेल या पासवर्ड गलत है। मरीज़ और फ़िज़ियोथेरेपिस्ट अलग-अलग पेज पर साइन इन करते हैं।',
  'If an account exists for this email, a password reset link has been sent.':
      'यदि इस ईमेल से कोई खाता है, तो पासवर्ड रीसेट लिंक भेज दिया गया है।',
  'Administrator accounts sign in on the web admin portal.':
      'एडमिन खाते वेब एडमिन पोर्टल पर साइन इन करते हैं।',
  'Open the admin portal in a web browser to manage accounts, doctor approvals and grievances.':
      'खाते, डॉक्टर स्वीकृति और शिकायतें संभालने के लिए वेब ब्राउज़र में एडमिन पोर्टल खोलें।',
  'Signed out on this device': 'इस डिवाइस से साइन आउट किया गया',
  'Your account was signed in on another device, so this device was signed out. Sign in again to continue here.':
      'आपका खाता किसी दूसरे डिवाइस पर साइन इन हुआ, इसलिए इस डिवाइस से साइन आउट किया गया। यहाँ जारी रखने के लिए फिर से साइन इन करें।',
  'Your account is now signed in on this device only. Any other device was signed out.':
      'आपका खाता अब केवल इसी डिवाइस पर साइन इन है। किसी अन्य डिवाइस से साइन आउट कर दिया गया।',
  'OK': 'ठीक है',
  'Sign in again': 'फिर से साइन इन करें',
  'Admin portal': 'एडमिन पोर्टल',
  'Administrator sign-in': 'एडमिन साइन-इन',
  'This account does not have administrator access.':
      'इस खाते को एडमिन की अनुमति नहीं है।',
  'You were signed out after 30 minutes without activity.':
      '30 मिनट तक कोई गतिविधि न होने पर आपको साइन आउट कर दिया गया।',
  'Add doctor': 'डॉक्टर जोड़ें',
  'Log out': 'लॉग आउट',

  // Grievances
  'Open': 'खुला',
  'Resolved': 'हल हुआ',
  'All': 'सभी',
  'Mark as resolved': 'हल हुआ चिह्नित करें',
  'Reopen': 'फिर से खोलें',
  'Reopen request': 'अनुरोध फिर से खोलें',
  'Mark this request as resolved?': 'क्या इस अनुरोध को हल हुआ चिह्नित करें?',
  'The person who raised it will be notified. They can reply to reopen it.':
      'अनुरोध भेजने वाले व्यक्ति को सूचना दी जाएगी। वे जवाब देकर इसे फिर से खोल सकते हैं।',
  'This request is resolved. Send a message to reopen it.':
      'यह अनुरोध हल हो चुका है। इसे फिर से खोलने के लिए संदेश भेजें।',
  'This request is resolved.': 'यह अनुरोध हल हो चुका है।',
  'Request marked as resolved.': 'अनुरोध हल हुआ चिह्नित किया गया।',
  'Request reopened.': 'अनुरोध फिर से खोला गया।',
  'No open requests.': 'कोई खुला अनुरोध नहीं।',
  'No resolved requests.': 'कोई हल हुआ अनुरोध नहीं।',
  'Help request resolved': 'सहायता अनुरोध हल हुआ',
  'Your help request was marked as resolved.':
      'आपका सहायता अनुरोध हल के रूप में चिह्नित किया गया है।',
  'Send message': 'संदेश भेजें',

  // Reminders
  'Exercise session starting soon': 'व्यायाम सत्र जल्द शुरू होगा',
  'Your scheduled session starts within 15 minutes.':
      'आपका निर्धारित सत्र 15 मिनट के भीतर शुरू होगा।',

  // Tutorials
  'Watch video tutorial': 'वीडियो ट्यूटोरियल देखें',
  'Could not open the video. Check your internet connection and try again.':
      'वीडियो नहीं खुल सका। इंटरनेट कनेक्शन जाँचें और फिर से प्रयास करें।',
  'Exercise tutorials': 'व्यायाम ट्यूटोरियल',
  'Add a YouTube link reviewed by your clinical team. Patients see it on the exercise guide.':
      'अपनी क्लिनिकल टीम द्वारा जाँचा गया YouTube लिंक जोड़ें। मरीज़ इसे व्यायाम गाइड में देखेंगे।',
  'YouTube link': 'YouTube लिंक',
  'Enter a YouTube link that starts with https://': 'https:// से शुरू होने वाला YouTube लिंक दें',
  'Tutorial saved.': 'ट्यूटोरियल सहेजा गया।',
  'Tutorial removed.': 'ट्यूटोरियल हटाया गया।',
  'No tutorial': 'कोई ट्यूटोरियल नहीं',
  'Save': 'सहेजें',
  'Remove': 'हटाएँ',
  'Video title': 'वीडियो का शीर्षक',
  'Add': 'जोड़ें',
  'Edit': 'बदलें',

  // Calibration
  'Movement calibration': 'गतिविधि कैलिब्रेशन',
  'Standard targets': 'मानक लक्ष्य',
  'Adaptive (from recent sessions)': 'अनुकूल (हाल के सत्रों से)',
  'Manual target': 'मैनुअल लक्ष्य',
  'Target angle (degrees)': 'लक्ष्य कोण (डिग्री)',
  'Adaptive targets start from the patient\'s recent best range and move toward the standard target in small steps. They never exceed the standard target.':
      'अनुकूल लक्ष्य मरीज़ की हाल की सर्वोत्तम सीमा से शुरू होकर छोटे चरणों में मानक लक्ष्य की ओर बढ़ते हैं। ये कभी मानक लक्ष्य से आगे नहीं जाते।',
  'Calibration saved.': 'कैलिब्रेशन सहेजा गया।',
  'Personalised target': 'व्यक्तिगत लक्ष्य',
  'Standard target': 'मानक लक्ष्य',
  'Not enough recent sessions yet; standard target in use.':
      'अभी पर्याप्त हाल के सत्र नहीं हैं; मानक लक्ष्य उपयोग में है।',
  'Uses measured thresholds; calibration is not available for this exercise.':
      'यह व्यायाम मापी गई सीमाओं का उपयोग करता है; इसके लिए कैलिब्रेशन उपलब्ध नहीं है।',
  'Enter a target between the start angle and the standard target.':
      'प्रारंभ कोण और मानक लक्ष्य के बीच लक्ष्य दर्ज करें।',

  // Exercise snapshots
  'Exercise snapshots': 'व्यायाम तस्वीरें',
  'Representative images selected automatically from each day\'s session.':
      'हर दिन के सत्र से स्वतः चुनी गई प्रतिनिधि तस्वीरें।',
  'No exercise snapshots yet.': 'अभी कोई व्यायाम तस्वीर नहीं।',
  'Could not load image.': 'तस्वीर लोड नहीं हुई।',
  'Research use permitted': 'शोध उपयोग की अनुमति',
  'Clinical review only': 'केवल क्लिनिकल समीक्षा',
  'Most representative': 'सबसे प्रतिनिधि',
  'Closest match': 'सबसे मिलती-जुलती',
};
