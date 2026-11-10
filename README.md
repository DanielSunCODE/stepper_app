# Motor a pasos BLE (servoapp)

Aplicación Flutter para controlar un motor a pasos **28BYJ-48** con driver **ULN2003** desde un **ESP32** por Bluetooth Low Energy (BLE).

## Características

- Conexión BLE al dispositivo `MOTORPASOS-ESP32` (también se filtra por el UUID del servicio).
- Verificación de permisos y del estado del Bluetooth antes de escanear.
- Dashboard con:
  - Gráfica en vivo del voltaje medido por el ADC.
  - Dial de posición con selección de ángulo destino.
  - Lecturas de ángulo, velocidad, voltaje y ADC.
  - Factor configurable del divisor de voltaje.
- Giro continuo horario/antihorario y paro del motor.
- Velocidad ajustable de 20 a 500 pasos/s.
- Modos de paso: simple, medio paso y doble paso.
- Movimiento por grados exactos o hacia un ángulo destino.

## Hardware

| Elemento | Conexión |
| --- | --- |
| Motor 28BYJ-48 + ULN2003 | IN1 → GPIO4, IN2 → GPIO5, IN3 → GPIO6, IN4 → GPIO7 |
| Medición de voltaje | Divisor de voltaje → GPIO1 (ADC) |
| Alimentación | Compartir GND entre ESP32 y driver |

El firmware está en [`esp32/motor_pasos_ble.ino`](esp32/motor_pasos_ble.ino). Se puede cargar con el Arduino IDE seleccionando una placa ESP32 y el monitor serie a **115200 baudios**.

## Requisitos

- Flutter **3.38.9** / Dart **3.10.8** (versión probada).
- Android 12 o superior para los permisos BLE, o iOS.
- ESP32 encendido y anunciando `MOTORPASOS-ESP32`.
- **No tener nRF Connect (u otro cliente BLE) conectado al ESP32**, porque el ESP32 deja de anunciarse mientras mantiene una conexión.

## Instalación y ejecución

```bash
flutter pub get
flutter devices
flutter run -d <device-id>
```

Para generar el APK de depuración:

```bash
flutter build apk --debug
```

Verificaciones del proyecto:

```bash
flutter analyze
flutter test
```

## Protocolo BLE

| Elemento | UUID |
| --- | --- |
| Servicio | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Comando (write / write-no-response) | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| Estado (notify) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |
| Telemetría (notify) | `6e400004-b5a3-f393-e0a9-e50e24dcca9e` |

### Comandos

| Comando | Acción |
| --- | --- |
| `F` | Giro continuo horario |
| `B` | Giro continuo antihorario |
| `X` | Detener motor |
| `S<n>` | Velocidad en pasos/s (20 a 500) |
| `M0` | Paso simple (2048 pasos/vuelta) |
| `M1` | Medio paso (4096 pasos/vuelta) |
| `M2` | Doble paso (2048 pasos/vuelta) |
| `G<grados>` | Mover grados y detenerse; positivo = horario, negativo = antihorario |

### Telemetría

Formato: `adc,angulo10,direccion,modo,velocidad`

- `angulo10`: ángulo en décimas de grado (`0..3599`).
- `direccion`: `1` horario, `-1` antihorario, `0` detenido.

## Estructura del proyecto

```text
lib/
  ble_controller.dart   Conexión BLE, comandos y telemetría
  main.dart             Dashboard y controles
  widgets.dart          Dial, gráfica, lecturas e indicadores
esp32/
  motor_pasos_ble.ino   Firmware del ESP32
test/
  widget_test.dart      Prueba del dashboard
```

## Solución de problemas

- **“El Bluetooth está apagado”**: activa el Bluetooth del teléfono y vuelve a pulsar Conectar.
- **“No se encontró el ESP32”**: verifica que el ESP32 esté encendido, cerca y que nRF Connect no esté conectado a él. También revisa que no esté conectado a otro teléfono.
- **Permisos denegados**: revisa Ajustes → Aplicaciones → servoapp → Permisos, y concede Bluetooth y ubicación.
- **Android Studio no detecta el teléfono**: confirma con `adb devices` que aparezca como `device`, activa la depuración USB y reinicia Android Studio para reiniciar el daemon de Flutter.

## Changelog

### 2026-11-10

#### Corregido

- La app ahora valida que el Bluetooth esté encendido antes de escanear y muestra un mensaje claro si está apagado, sin permisos, sin ubicación o no es compatible con BLE.
- Detección del ESP32 cuando el nombre se anuncia como `MOTORPASOS-ESP32`: la comparación ya no distingue mayúsculas/minúsculas.
- Eliminado `dart:io` del controlador BLE para permitir la compilación web.
- Proyecto compatible con Flutter 3.38.9 / Dart 3.10.8.

#### Agregado

- Mensaje de estado visible al inicio del dashboard, sin necesidad de hacer scroll.
- Documentación del proyecto y este changelog.

#### Cambiado

- `flutter_reactive_ble` 5.6.0 → 5.4.2.
- `permission_handler` 13.0.2 → 12.0.3.
- Gradle 9.3.1 → 8.14, AGP 9.1.0 → 8.11.1, Kotlin 2.4.0 → 2.2.20.
- `compileSdk` 37 → 36 y restauración del plugin `kotlin-android`.

### 1.0.0

- Versión inicial: conexión BLE, dashboard, telemetría y control del motor a pasos.
