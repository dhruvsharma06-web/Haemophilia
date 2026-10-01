import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/screens/auth/health_screening_screen.dart';
import 'package:haemophilia_app/screens/auth/login_screen.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';

Widget createTestApp(Widget child, [String locale = 'en']) {
  AppLocaleService.currentLocale.value = locale;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, c) => AppLocaleScope(
      notifier: AppLocaleService.currentLocale,
      child: c!,
    ),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screenSizes = [
    const Size(320, 640), // Narrow phone (320px)
    const Size(360, 780), // Standard Android (360px)
    const Size(375, 812), // iPhone SE / Mini (375px)
    const Size(390, 844), // iPhone 12/13/14 (390px)
    const Size(414, 896), // iPhone Plus / Max (414px)
  ];

  group('Patient Login Health Screening Widget Tests', () {
    for (final size in screenSizes) {
      testWidgets('Renders screening card at ${size.width}x${size.height} with 0 overflow (EN & HI)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // English
        await tester.pumpWidget(createTestApp(const LoginScreen(), 'en'));
        await tester.pumpAndSettle();

        expect(find.text('Health Risk Screening'), findsOneWidget);
        expect(find.text('Start ›'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('स्वास्थ्य जोखिम जाँच'), findsOneWidget);
        expect(find.text('शुरू करें ›'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch back to English
        AppLocaleService.currentLocale.value = 'en';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Health Risk Screening'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('HealthScreeningScreen Responsive & Localization Tests', () {
    for (final size in screenSizes) {
      testWidgets('Screening flow at ${size.width}x${size.height} with 0 overflow (EN & HI)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // English
        await tester.pumpWidget(createTestApp(const HealthScreeningScreen(), 'en'));
        await tester.pumpAndSettle();

        expect(find.text('Health Risk Screening'), findsOneWidget);
        expect(find.text('Screening Guidance'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('स्वास्थ्य जोखिम जाँच'), findsOneWidget);
        expect(find.text('जाँच मार्गदर्शन'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Switch back to English
        AppLocaleService.currentLocale.value = 'en';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Health Risk Screening'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Screening flow with virtual keyboard (viewInsets.bottom = 300)',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(createTestApp(const HealthScreeningScreen(), 'en'));
      await tester.pumpAndSettle();

      expect(find.text('Health Risk Screening'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Instant Translation Map Verification', () {
    test('Exercise cards and dashboard terms translate properly', () {
      AppLocaleService.currentLocale.value = 'hi';
      expect(tr('Clinically Validated'), 'चिकित्सकीय रूप से मान्य');
      expect(tr('Needs Practice'), 'अभ्यास की आवश्यकता');
      expect(tr('Completed (Needs Practice)'), 'पूर्ण (अभ्यास आवश्यक)');
      expect(tr('Most Recent Focus'), 'हाल का मुख्य ध्यान');
      expect(tr('EXERCISES'), 'व्यायाम');
      expect(tr('CORRECT REPS'), 'सही रेप्स');
      expect(tr('AVG SCORE'), 'औसत स्कोर');
      expect(tr('Today'), 'आज');
      expect(tr('Health Risk Screening'), 'स्वास्थ्य जोखिम जाँच');
      expect(tr('Healthy'), 'स्वस्थ');
      expect(tr('Mild'), 'हल्का जोखिम');
      expect(tr('Moderate'), 'मध्यम जोखिम');
      expect(tr('Severe'), 'गंभीर जोखिम');

      // Switch back
      AppLocaleService.currentLocale.value = 'en';
      expect(tr('Clinically Validated'), 'Clinically Validated');
      expect(tr('Health Risk Screening'), 'Health Risk Screening');
    });
  });
}
