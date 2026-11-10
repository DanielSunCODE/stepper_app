import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

final _service = Uuid.parse('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
final _command = Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a8');
final _status = Uuid.parse('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
final _telemetry = Uuid.parse('6e400004-b5a3-f393-e0a9-e50e24dcca9e');
const _devicePrefix = 'MotorPasos';

/// Tipo de movimiento del motor (índice = número que espera el firmware: M0/M1/M2).
enum StepMode {
  simple('Paso simple', 'Una bobina', 2048),
  half('Medio paso', 'Mayor resolución', 4096),
  double_('Doble paso', 'Dos bobinas, más torque', 2048);

  const StepMode(this.label, this.hint, this.stepsPerRev);
  final String label;
  final String hint;
  final int stepsPerRev;
}

enum Link { disconnected, scanning, connecting, connected }

/// Conexión BLE con el ESP32 + estado de telemetría para el dashboard.
class MotorController extends ChangeNotifier {
  static const maxSamples = 200;

  late final _ble = FlutterReactiveBle(); // lazy: el plugin nativo solo se inicia al conectar
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _teleSub;
  StreamSubscription<List<int>>? _statusSub;
  QualifiedCharacteristic? _cmdChar;
  bool _synced = false; // mode/speed se toman del ESP32 solo en la primera lectura

  Link link = Link.disconnected;
  String deviceName = '';
  String message = 'Pulsa Conectar.';

  // Telemetría
  int adc = 0;
  double angle = 0;
  int direction = 0; // 1 horario, -1 antihorario, 0 detenido
  StepMode mode = StepMode.half;
  int speed = 200; // pasos/s
  final Queue<double> samplesMv = Queue();

  /// Factor del divisor de voltaje externo (ADC máx. 3.3 V).
  double dividerFactor = 1.0;

  bool get connected => link == Link.connected;
  double get millivolts => adc / 4095 * 3300 * dividerFactor;
  bool get moving => direction != 0;

  // ------------------------------------------------------------ conexión
  Future<void> connect() async {
    if (link != Link.disconnected) return;
    if (!await _ensurePermissions()) {
      _setMessage('Faltan permisos de Bluetooth.');
      return;
    }
    final seen = <String>{};
    link = Link.scanning;
    _setMessage('Buscando MotorPasos-ESP32...');

    final timeout = Timer(const Duration(seconds: 12), () {
      if (link == Link.scanning) {
        _scanSub?.cancel();
        link = Link.disconnected;
        _setMessage('No se encontró el ESP32 (${seen.length} dispositivos vistos). '
            '¿Tiene el sketch cargado, está encendido y sin otro cliente conectado?');
      }
    });

    // Sin filtro de servicio: el nombre o el UUID pueden venir en el anuncio o en el scan response.
    _scanSub = _ble.scanForDevices(withServices: const []).listen((d) {
      if (link != Link.scanning) return;
      if (seen.add(d.id)) _setMessage('Buscando MotorPasos-ESP32... (${seen.length} dispositivos vistos)');
      final isOurs = d.name.startsWith(_devicePrefix) || d.serviceUuids.contains(_service);
      if (!isOurs) return;
      timeout.cancel();
      _scanSub?.cancel();
      _connectTo(d);
    }, onError: (Object e) {
      timeout.cancel();
      link = Link.disconnected;
      _setMessage('Error al escanear: $e');
    });
    notifyListeners();
  }

  void _connectTo(DiscoveredDevice d) {
    link = Link.connecting;
    deviceName = d.name.isEmpty ? 'ESP32' : d.name;
    _setMessage('Conectando...');
    _connSub = _ble
        .connectToDevice(id: d.id, connectionTimeout: const Duration(seconds: 10))
        .listen((u) async {
      switch (u.connectionState) {
        case DeviceConnectionState.connected:
          await _onConnected(d.id);
        case DeviceConnectionState.disconnected:
          _onDisconnected(u.failure?.message);
        default:
          break;
      }
    });
  }

  Future<void> _onConnected(String id) async {
    _cmdChar = QualifiedCharacteristic(serviceId: _service, characteristicId: _command, deviceId: id);
    final tele = QualifiedCharacteristic(serviceId: _service, characteristicId: _telemetry, deviceId: id);
    final stat = QualifiedCharacteristic(serviceId: _service, characteristicId: _status, deviceId: id);
    try {
      // Pide más MTU y da tiempo al ESP32 para registrar las notificaciones.
      if (Platform.isAndroid) await _ble.requestMtu(deviceId: id, mtu: 64);
    } catch (_) {}
    _teleSub = _ble.subscribeToCharacteristic(tele).listen(_onTelemetry);
    _statusSub = _ble
        .subscribeToCharacteristic(stat)
        .listen((d) => _setMessage(String.fromCharCodes(d)));
    link = Link.connected;
    _setMessage('Conectado.');
  }

  void _onDisconnected(String? error) {
    _teleSub?.cancel();
    _statusSub?.cancel();
    _cmdChar = null;
    _synced = false;
    direction = 0;
    link = Link.disconnected;
    _setMessage(error == null ? 'Desconectado.' : 'Desconectado: $error');
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _connSub?.cancel(); // cancelar la suscripción cierra la conexión
    _connSub = null;
    _onDisconnected(null);
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final res = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // Android <= 11
    ].request();
    final scan = res[Permission.bluetoothScan]!;
    final conn = res[Permission.bluetoothConnect]!;
    // En Android <= 11 estos devuelven "denied/restricted" aunque el escaneo funcione
    // con la ubicación; solo bloqueamos si el usuario los negó de forma permanente.
    return !(scan.isPermanentlyDenied || conn.isPermanentlyDenied);
  }

  // ------------------------------------------------------------ telemetría
  void _onTelemetry(List<int> data) {
    final p = String.fromCharCodes(data).trim().split(',');
    if (p.length < 3) return;
    final v = p.map(int.tryParse).toList();
    if (v.contains(null)) return;
    adc = v[0]!;
    angle = v[1]! / 10;
    direction = v[2]!;
    if (p.length >= 5 && !_synced) {
      _synced = true;
      mode = StepMode.values[v[3]!.clamp(0, 2)];
      speed = v[4]!;
    }
    samplesMv.addLast(millivolts);
    while (samplesMv.length > maxSamples) {
      samplesMv.removeFirst();
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- comandos
  Future<void> _send(String cmd) async {
    final c = _cmdChar;
    if (c == null) return;
    try {
      await _ble.writeCharacteristicWithoutResponse(c, value: cmd.codeUnits);
    } catch (e) {
      _setMessage('Error al enviar: $e');
    }
  }

  /// Gira de forma continua. [clockwise] true = horario.
  Future<void> spin({required bool clockwise}) async {
    await _send('M${mode.index}');
    await _send('S$speed');
    await _send(clockwise ? 'F' : 'B');
  }

  Future<void> stop() => _send('X');

  /// Mueve [degrees] grados (siempre positivo) en el sentido indicado y se detiene.
  Future<void> moveBy(double degrees, {required bool clockwise}) async {
    if (degrees <= 0) return;
    await _send('M${mode.index}');
    await _send('S$speed');
    await _send('G${clockwise ? '' : '-'}${degrees.toStringAsFixed(1)}');
  }

  /// Va a un ángulo absoluto por el camino más corto.
  Future<void> goTo(double target) async {
    var delta = (target - angle) % 360;
    if (delta > 180) delta -= 360;
    if (delta.abs() < 0.2) return;
    await moveBy(delta.abs(), clockwise: delta > 0);
  }

  Future<void> setMode(StepMode m) async {
    mode = m;
    notifyListeners();
    await _send('M${m.index}');
  }

  Future<void> setSpeed(int s) async {
    speed = s;
    notifyListeners();
    await _send('S$s');
  }

  void setDividerFactor(double f) {
    dividerFactor = f < 1 ? 1 : f;
    notifyListeners();
  }

  void _setMessage(String m) {
    message = m;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _teleSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
