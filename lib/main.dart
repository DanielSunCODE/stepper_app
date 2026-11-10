import 'package:flutter/material.dart';

import 'ble_controller.dart';
import 'widgets.dart';

void main() => runApp(const ServoApp());

class ServoApp extends StatelessWidget {
  const ServoApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kCw, brightness: b),
        );
    return MaterialApp(
      title: 'Motor a pasos',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final m = MotorController();
  double? target; // destino elegido tocando el dial
  final degreesCtrl = TextEditingController(text: '90');

  @override
  void dispose() {
    degreesCtrl.dispose();
    m.dispose();
    super.dispose();
  }

  double get degrees => double.tryParse(degreesCtrl.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Motor a pasos'),
          actions: [_connectionChip(), const SizedBox(width: 8)],
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 820;
            final left = [_scopeCard(), _dialCard(), _readouts()];
            final right = [_modeCard(), _spinCard(), _moveCard()];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    m.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(children: _spaced(left))),
                    const SizedBox(width: 16),
                    Expanded(child: Column(children: _spaced(right))),
                  ])
                else
                  ..._spaced([...left, ...right]),
              ],
            );
          }),
        ),
      ),
    );
  }

  List<Widget> _spaced(List<Widget> w) => [for (final x in w) Padding(padding: const EdgeInsets.only(bottom: 12), child: x)];

  // ---------------------------------------------------------------- cabecera
  Widget _connectionChip() {
    final busy = m.link == Link.scanning || m.link == Link.connecting;
    return FilledButton.tonalIcon(
      onPressed: busy ? null : (m.connected ? m.disconnect : m.connect),
      icon: busy
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(m.connected ? Icons.bluetooth_connected : Icons.bluetooth),
      label: Text(switch (m.link) {
        Link.disconnected => 'Conectar',
        Link.scanning => 'Buscando',
        Link.connecting => 'Conectando',
        Link.connected => 'Desconectar',
      }),
    );
  }

  Widget _card(String title, Widget child) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );

  // --------------------------------------------------------------- dashboard
  Widget _scopeCard() {
    final maxMv = 3300 * m.dividerFactor;
    return _card(
      'Voltaje del motor (ADC)',
      Column(children: [
        Container(
          height: 150,
          decoration: BoxDecoration(color: kScreen, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(6),
          child: Scope(samples: m.samplesMv.toList(), maxMv: maxMv, capacity: MotorController.maxSamples),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('Factor del divisor', overflow: TextOverflow.ellipsis)),
          IconButton(
              onPressed: () => m.setDividerFactor(m.dividerFactor - 0.05),
              icon: const Icon(Icons.remove_circle_outline)),
          Text(m.dividerFactor.toStringAsFixed(2)),
          IconButton(
              onPressed: () => m.setDividerFactor(m.dividerFactor + 0.05),
              icon: const Icon(Icons.add_circle_outline)),
        ]),
      ]),
    );
  }

  Widget _dialCard() {
    return _card(
      'Posición',
      Column(children: [
        Dial(
          angle: m.angle,
          direction: m.direction,
          target: target,
          onTarget: (t) => setState(() => target = t),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          DirLed(label: 'Antihorario', on: m.direction == -1, color: kCcw),
          DirLed(label: 'Horario', on: m.direction == 1, color: kCw),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(
              target == null ? 'Toca el dial para elegir un ángulo destino.' : 'Destino: ${target!.toStringAsFixed(1)}°',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (target != null) TextButton(onPressed: () => setState(() => target = null), child: const Text('Quitar')),
          FilledButton.icon(
            onPressed: m.connected && target != null ? () => m.goTo(target!) : null,
            icon: const Icon(Icons.my_location),
            label: const Text('Ir'),
          ),
        ]),
      ]),
    );
  }

  Widget _readouts() {
    final steps = m.mode.stepsPerRev;
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Readout(title: 'Ángulo', value: m.angle.toStringAsFixed(1), unit: '°'),
        Readout(title: 'Velocidad', value: m.moving ? '${m.speed}' : '0', unit: 'pasos/s'),
        Readout(title: 'Voltaje', value: m.millivolts.round().toString(), unit: 'mV'),
        Readout(title: 'ADC', value: '${m.adc}', unit: '/ 4095'),
        Readout(title: 'Modo', value: m.mode.label),
        Readout(title: 'Pasos por vuelta', value: '$steps'),
      ],
    );
  }

  // ----------------------------------------------------------------- control
  Widget _modeCard() {
    return _card(
      'Tipo de movimiento',
      Column(children: [
        SegmentedButton<StepMode>(
          showSelectedIcon: false,
          segments: [
            for (final s in StepMode.values) ButtonSegment(value: s, label: Text(s.label, textAlign: TextAlign.center)),
          ],
          selected: {m.mode},
          onSelectionChanged: m.connected ? (s) => m.setMode(s.first) : null,
        ),
        const SizedBox(height: 8),
        Text(m.mode.hint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Velocidad'),
          Expanded(
            child: Slider(
              min: 20,
              max: 500,
              divisions: 48,
              value: m.speed.toDouble().clamp(20, 500),
              label: '${m.speed} pasos/s',
              onChanged: m.connected ? (v) => setState(() => m.speed = v.round()) : null,
              onChangeEnd: m.connected ? (v) => m.setSpeed(v.round()) : null,
            ),
          ),
          SizedBox(width: 44, child: Text('${m.speed}', textAlign: TextAlign.end)),
        ]),
      ]),
    );
  }

  Widget _spinCard() {
    final on = m.connected;
    return _card(
      'Giro continuo',
      Column(children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kCcw, minimumSize: const Size.fromHeight(56)),
              onPressed: on ? () => m.spin(clockwise: false) : null,
              icon: const Icon(Icons.rotate_left),
              label: const Text('Antihorario'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kCw, minimumSize: const Size.fromHeight(56)),
              onPressed: on ? () => m.spin(clockwise: true) : null,
              icon: const Icon(Icons.rotate_right),
              label: const Text('Horario'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: on ? m.stop : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Parar motor'),
        ),
      ]),
    );
  }

  Widget _moveCard() {
    final on = m.connected;
    return _card(
      'Mover grados exactos',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: [
          for (final d in [15, 45, 90, 180, 360])
            ActionChip(label: Text('$d°'), onPressed: () => setState(() => degreesCtrl.text = '$d')),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: degreesCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Grados', suffixText: '°', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: kCcw),
              onPressed: on && degrees > 0 ? () => m.moveBy(degrees, clockwise: false) : null,
              icon: const Icon(Icons.undo),
              label: const Text('Antihorario'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: kCw),
              onPressed: on && degrees > 0 ? () => m.moveBy(degrees, clockwise: true) : null,
              icon: const Icon(Icons.redo),
              label: const Text('Horario'),
            ),
          ),
        ]),
      ]),
    );
  }
}
