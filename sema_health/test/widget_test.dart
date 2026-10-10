import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sema_health/main.dart';

void main() {
  testWidgets('App boots to language screen', (tester) async {
    await tester.pumpWidget(const SemaApp());
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('Choose your'),
      ),
      findsOneWidget,
    );
  });
}
