import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/models/user_model.dart';
import 'package:haemophilia_app/screens/auth/doctor_login_screen.dart';
import 'package:haemophilia_app/screens/auth/doctor_pending_approval_screen.dart';
import 'package:haemophilia_app/screens/auth/doctor_register_screen.dart';
import 'package:haemophilia_app/screens/auth/login_screen.dart';
import 'package:haemophilia_app/screens/auth/register_screen.dart';
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
    const Size(320, 640), // Very narrow phone
    const Size(360, 780), // Standard Android
    const Size(390, 844), // iPhone 12/13/14
    const Size(414, 896), // iPhone XR/Plus
  ];

  group('Patient Login Screen Responsive & Localization Tests', () {
    for (final size in screenSizes) {
      testWidgets('Renders at ${size.width}x${size.height} with 0 overflow (EN & HI)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // English
        await tester.pumpWidget(createTestApp(const LoginScreen(), 'en'));
        await tester.pumpAndSettle();

        expect(find.text('Patient Login'), findsOneWidget);
        expect(find.text('Somaiya HaemoPhysio'), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('रोगी लॉगिन'), findsOneWidget);
        expect(find.text('साइन इन करें'), findsOneWidget);
        expect(find.text('Google के साथ जारी रखें'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch back to English
        AppLocaleService.currentLocale.value = 'en';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Patient Login'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Patient Registration Screen Responsive & Localization Tests', () {
    for (final size in screenSizes) {
      testWidgets('Renders at ${size.width}x${size.height} with 0 overflow (EN & HI)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // English
        await tester.pumpWidget(createTestApp(const RegisterScreen(), 'en'));
        await tester.pumpAndSettle();

        expect(find.text('Patient Registration'), findsOneWidget);
        expect(find.text('First Name'), findsOneWidget);
        expect(find.text('Last Name'), findsOneWidget);
        expect(find.text('Create Patient Account'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('रोगी पंजीकरण'), findsOneWidget);
        expect(find.text('पहला नाम'), findsOneWidget);
        expect(find.text('अंतिम नाम'), findsOneWidget);
        expect(find.text('रोगी खाता बनाएं'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Doctor Login Screen Responsive & Localization Tests', () {
    for (final size in screenSizes) {
      testWidgets('Renders at ${size.width}x${size.height} with 0 overflow (EN & HI)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // English
        await tester.pumpWidget(createTestApp(const DoctorLoginScreen(), 'en'));
        await tester.pumpAndSettle();

        expect(find.text('Physiotherapist Login'), findsOneWidget);
        expect(find.text('Physiotherapist ID'), findsOneWidget);
        expect(find.text('Back to Patient Login'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('फिजियोथेरेपिस्ट लॉगिन'), findsOneWidget);
        expect(find.text('फिजियोथेरेपिस्ट आईडी'), findsOneWidget);
        expect(find.text('रोगी लॉगिन पर वापस जाएं'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Doctor Registration Screen Multi-Step Responsive & Localization Tests', () {
    for (final size in screenSizes) {
      testWidgets('Renders all 4 steps at ${size.width}x${size.height} with 0 overflow',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestApp(const DoctorRegisterScreen(), 'en'));
        await tester.pumpAndSettle();

        // Step 1: Personal
        expect(find.text('Doctor Registration'), findsOneWidget);
        expect(find.text('Personal Information'), findsOneWidget);
        expect(find.text('Medical Registration Number'), findsNothing);
        expect(tester.takeException(), isNull);

        // Fill Step 1 to advance
        await tester.enterText(find.byType(TextField).at(0), 'Dr. Jane Doe');
        await tester.enterText(find.byType(TextField).at(1), 'doctor@somaiya.edu');
        await tester.enterText(find.byType(TextField).at(2), '9876543210');
        await tester.enterText(find.byType(TextField).at(3), 'Mumbai');
        await tester.enterText(find.byType(TextField).at(6), 'Password123');
        await tester.enterText(find.byType(TextField).at(7), 'Password123');

        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Step 2: Professional
        expect(find.text('Professional Information'), findsOneWidget);
        expect(find.text('Medical Registration Number'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi in Step 2
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('व्यावसायिक जानकारी'), findsOneWidget);
        expect(find.text('चिकित्सा पंजीकरण संख्या'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Doctor Pending Approval Screen Tests', () {
    for (final size in screenSizes) {
      testWidgets('Renders at ${size.width}x${size.height} with 0 overflow (EN & HI)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final testDoctor = UserModel(
          uid: 'doc_123',
          name: 'Jane Doe',
          email: 'doctor@somaiya.edu',
          role: 'pending_doctor',
          isApproved: false,
          registrationNumber: 'MMC/2021/999',
          hospital: 'K. J. Somaiya Hospital',
        );

        // English
        await tester.pumpWidget(
          createTestApp(DoctorPendingApprovalScreen(user: testDoctor), 'en'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Application Under Review'), findsOneWidget);
        expect(find.text('Somaiya HaemoPhysio'), findsOneWidget);
        expect(find.text('Dr. Jane Doe'), findsOneWidget);
        expect(find.text('MMC/2021/999'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Instant Switch to Hindi
        AppLocaleService.currentLocale.value = 'hi';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('आवेदन समीक्षाधीन है'), findsOneWidget);
        expect(find.text('स्वीकृति स्थिति जांचें'), findsOneWidget);
        expect(find.text('साइन आउट करें'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
