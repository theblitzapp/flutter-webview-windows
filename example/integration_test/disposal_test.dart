import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_windows/webview_windows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'disposing of a webview does not cause a crash',
    (WidgetTester tester) async {
      for (var i = 0; i < 16; i++) {
        final controller = WebviewController();
        await controller.initialize();

        await tester.pumpWidget(Webview(
          key: ValueKey(i),
          controller: controller,
        ));

        await tester.pumpAndSettle();

        await controller.dispose();
      }
    },
  );
}
