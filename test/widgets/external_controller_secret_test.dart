import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _secretLabel = 'Secret';
const _controllerLabel = 'External controller';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpGeneralView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1000, 3000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: GeneralView()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openControllerDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ListItem, _controllerLabel));
    await tester.pumpAndSettle();
  }

  Future<void> toggleControllerInDialog(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(FormPage),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submitDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  Finder secretField() => find.descendant(
    of: find.widgetWithText(FormRow, _secretLabel),
    matching: find.byType(TextFormField),
  );

  testWidgets('the secret lives in the form, not in the settings list', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    await openControllerDialog(tester);
    expect(find.text(_secretLabel), findsNothing);

    await toggleControllerInDialog(tester);
    expect(find.text(_secretLabel), findsOneWidget);

    await submitDialog(tester);

    final config = container.read(patchClashConfigProvider);
    expect(config.externalController, '127.0.0.1:9090');
    expect(config.secret, hasLength(32));
    expect(find.text(_secretLabel), findsNothing);
  });

  testWidgets('enabling the controller fills in a generated secret', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    await openControllerDialog(tester);
    await toggleControllerInDialog(tester);

    final field = tester.widget<TextFormField>(secretField());
    expect(field.controller!.text, hasLength(32));
  });

  testWidgets('a secret typed into the form replaces the generated one', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    await openControllerDialog(tester);
    await toggleControllerInDialog(tester);

    await tester.enterText(secretField(), '  my-own-secret ');
    await submitDialog(tester);

    expect(container.read(patchClashConfigProvider).secret, 'my-own-secret');
  });

  testWidgets('an emptied secret is generated again on save', (tester) async {
    await pumpGeneralView(tester);
    await openControllerDialog(tester);
    await toggleControllerInDialog(tester);

    await tester.enterText(secretField(), '   ');
    await submitDialog(tester);

    expect(container.read(patchClashConfigProvider).secret, hasLength(32));
  });

  testWidgets('closing the controller drops the secret', (tester) async {
    await pumpGeneralView(tester);
    await openControllerDialog(tester);
    await toggleControllerInDialog(tester);
    await submitDialog(tester);

    await openControllerDialog(tester);
    await toggleControllerInDialog(tester);
    expect(find.text(_secretLabel), findsNothing);
    await submitDialog(tester);

    expect(container.read(patchClashConfigProvider).externalController, '');
    expect(container.read(patchClashConfigProvider).secret, isEmpty);
  });
}
