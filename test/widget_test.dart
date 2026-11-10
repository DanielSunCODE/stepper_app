import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:servoapp/main.dart';

void main() {
  testWidgets('El dashboard muestra los controles principales', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ServoApp());

    expect(find.text('Conectar'), findsOneWidget);
    expect(find.text('Paso simple'), findsWidgets);
    expect(find.text('Medio paso'), findsWidgets);
    expect(find.text('Doble paso'), findsWidgets);
    expect(find.text('Parar motor'), findsOneWidget);
  });
}
