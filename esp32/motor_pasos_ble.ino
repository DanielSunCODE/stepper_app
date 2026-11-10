// Motor a pasos (28BYJ-48 + ULN2003) controlado por BLE desde la app Flutter.
//
// Comandos (escritos en COMMAND_UUID, texto ASCII):
//   F        gira horario de forma continua
//   B        gira antihorario de forma continua
//   X        detiene el motor
//   S<n>     velocidad en pasos/s (20..500)
//   M0       modo paso simple  (una bobina, 2048 pasos/vuelta)
//   M1       medio paso        (4096 pasos/vuelta)
//   M2       modo doble paso   (dos bobinas, 2048 pasos/vuelta)
//   G<grados> mueve los grados indicados y se detiene; positivo = horario,
//            negativo = antihorario (ej. G90, G-45.5)
//
// Telemetria (TELEMETRY_UUID, notify, <= 20 bytes): "adc,angulo10,dir,modo,vel"
//   angulo10 = angulo en decimas de grado (0..3599), dir = 1 / -1 / 0

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define IN1_PIN 4
#define IN2_PIN 5
#define IN3_PIN 6
#define IN4_PIN 7
#define ADC_PIN 1

// Depuracion por Serial (Monitor Serie a 115200 baudios). Ponlo en false para silenciarlo.
#define DEBUG_SERIAL true
#define DBG(...) do { if (DEBUG_SERIAL) Serial.printf(__VA_ARGS__); } while (0)

static const char *DEVICE_NAME = "MotorPasos-ESP32";
static const char *SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static const char *COMMAND_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
static const char *STATUS_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
static const char *TELEMETRY_UUID = "6e400004-b5a3-f393-e0a9-e50e24dcca9e";

const uint8_t motorPins[] = {IN1_PIN, IN2_PIN, IN3_PIN, IN4_PIN};
const int HALF_STEPS_PER_REV = 4096;

// Secuencia de medio paso. Indices pares = una bobina (paso simple),
// indices impares = dos bobinas (doble paso).
const uint8_t halfStepSequence[8][4] = {
  {1, 0, 0, 0}, {1, 1, 0, 0}, {0, 1, 0, 0}, {0, 1, 1, 0},
  {0, 0, 1, 0}, {0, 0, 1, 1}, {0, 0, 0, 1}, {1, 0, 0, 1}
};

enum StepMode : uint8_t { MODE_SIMPLE = 0, MODE_HALF = 1, MODE_DOUBLE = 2 };

BLECharacteristic *statusCharacteristic = nullptr;
BLECharacteristic *telemetryCharacteristic = nullptr;
volatile long stepPosition = 0;  // siempre en medios pasos
uint32_t lastTelemetryMs = 0;
uint32_t lastHeartbeatMs = 0;
volatile bool clientConnected = false;
volatile bool running = false;
volatile int direction = 1;
volatile uint16_t requestedSpeed = 200;
volatile StepMode stepMode = MODE_HALF;
volatile long remainingSteps = -1;  // -1 = continuo; >0 = pasos que faltan
int sequenceIndex = 0;
uint32_t lastStepMicros = 0;

int halfStepsPerStep() { return stepMode == MODE_HALF ? 1 : 2; }

void publishStatus(const char *message) {
  DBG("[STATUS] %s\n", message);
  if (statusCharacteristic != nullptr && clientConnected) {
    statusCharacteristic->setValue(message);
    statusCharacteristic->notify();
  }
}

void publishTelemetry() {
  if (telemetryCharacteristic == nullptr || !clientConnected) return;
  int adc = analogRead(ADC_PIN);
  long pos = ((stepPosition % HALF_STEPS_PER_REV) + HALF_STEPS_PER_REV) % HALF_STEPS_PER_REV;
  int angle10 = pos * 3600L / HALF_STEPS_PER_REV;
  int dir = running ? direction : 0;
  char msg[24];
  snprintf(msg, sizeof(msg), "%d,%d,%d,%d,%d", adc, angle10, dir, (int)stepMode, (int)requestedSpeed);
  telemetryCharacteristic->setValue(msg);
  telemetryCharacteristic->notify();
}

void releaseMotor() {
  for (uint8_t pin : motorPins) digitalWrite(pin, LOW);
}

void driveCurrentStep() {
  for (uint8_t i = 0; i < 4; i++) {
    digitalWrite(motorPins[i], halfStepSequence[sequenceIndex][i] ? HIGH : LOW);
  }
}

void stopMotor(const char *status) {
  running = false;
  remainingSteps = -1;
  releaseMotor();
  publishStatus(status);
}

// Alinea la secuencia a la paridad del modo: simple = indice par, doble = impar.
void applyMode(StepMode mode) {
  stepMode = mode;
  if (mode == MODE_SIMPLE) sequenceIndex &= ~1;
  else if (mode == MODE_DOUBLE) sequenceIndex |= 1;
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    clientConnected = true;
    DBG("[BLE] Cliente CONECTADO\n");
    publishStatus("Conectado");
  }

  void onDisconnect(BLEServer *server) override {
    clientConnected = false;
    running = false;
    remainingSteps = -1;
    releaseMotor();
    DBG("[BLE] Cliente DESCONECTADO, reanudando publicidad\n");
    delay(100);
    server->startAdvertising();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String command = characteristic->getValue().c_str();
    command.trim();
    command.toUpperCase();
    DBG("[CMD] recibido: '%s'\n", command.c_str());

    if (command == "F") {
      direction = 1;
      remainingSteps = -1;
      running = true;
      publishStatus("Girando horario");
    } else if (command == "B") {
      direction = -1;
      remainingSteps = -1;
      running = true;
      publishStatus("Girando antihorario");
    } else if (command == "X") {
      stopMotor("Parado");
    } else if (command.startsWith("S")) {
      int newSpeed = command.substring(1).toInt();
      if (newSpeed >= 20 && newSpeed <= 500) {
        requestedSpeed = newSpeed;
        char response[40];
        snprintf(response, sizeof(response), "Velocidad %d pasos/s", newSpeed);
        publishStatus(response);
      } else {
        publishStatus("Use S20 a S500");
      }
    } else if (command.startsWith("M")) {
      int m = command.substring(1).toInt();
      if (command.length() > 1 && m >= 0 && m <= 2) {
        applyMode((StepMode)m);
        publishStatus(m == 0 ? "Modo paso simple" : m == 1 ? "Modo medio paso" : "Modo doble paso");
      } else {
        publishStatus("Use M0, M1 o M2");
      }
    } else if (command.startsWith("G")) {
      float degrees = command.substring(1).toFloat();
      if (degrees == 0) {
        publishStatus("Use G<grados>, ej. G90");
        return;
      }
      direction = degrees > 0 ? 1 : -1;
      float absDegrees = fabsf(degrees);
      long steps = lroundf(absDegrees / 360.0f * HALF_STEPS_PER_REV / halfStepsPerStep());
      if (steps < 1) steps = 1;
      remainingSteps = steps;
      running = true;
      char response[40];
      snprintf(response, sizeof(response), "Moviendo %.1f grados", degrees);
      publishStatus(response);
    } else {
      publishStatus("Comandos: F B X S M G");
    }
  }
};

void setup() {
  if (DEBUG_SERIAL) {
    Serial.begin(115200);
    delay(1000);  // da tiempo a abrir el Monitor Serie
  }
  DBG("\n=== Motor a pasos BLE: arrancando ===\n");
  for (uint8_t pin : motorPins) pinMode(pin, OUTPUT);
  releaseMotor();

  BLEDevice::init(DEVICE_NAME);
  DBG("[BLE] Nombre: %s\n", DEVICE_NAME);
  DBG("[BLE] Direccion: %s\n", BLEDevice::getAddress().toString().c_str());
  DBG("[BLE] Servicio: %s\n", SERVICE_UUID);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *commandCharacteristic = service->createCharacteristic(
      COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  commandCharacteristic->setCallbacks(new CommandCallbacks());

  statusCharacteristic = service->createCharacteristic(
      STATUS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  statusCharacteristic->addDescriptor(new BLE2902());
  statusCharacteristic->setValue("Listo");

  telemetryCharacteristic = service->createCharacteristic(
      TELEMETRY_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  telemetryCharacteristic->addDescriptor(new BLE2902());

  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  DBG("[BLE] Publicidad iniciada: busca '%s' en la app\n", DEVICE_NAME);
}

void loop() {
  if (DEBUG_SERIAL && millis() - lastHeartbeatMs >= 2000) {
    lastHeartbeatMs = millis();
    DBG("[HB] t=%lus cliente=%s corriendo=%s dir=%d modo=%d vel=%u pos=%ld adc=%d\n",
        millis() / 1000, clientConnected ? "SI" : "no", running ? "SI" : "no", direction,
        (int)stepMode, (unsigned)requestedSpeed, stepPosition, analogRead(ADC_PIN));
  }

  if (millis() - lastTelemetryMs >= 100) {
    lastTelemetryMs = millis();
    publishTelemetry();
  }

  if (!running) {
    delay(10);
    return;
  }

  const uint32_t intervalMicros = 1000000UL / requestedSpeed;
  const uint32_t now = micros();
  if ((uint32_t)(now - lastStepMicros) >= intervalMicros) {
    lastStepMicros = now;
    const int hs = halfStepsPerStep();
    sequenceIndex = (sequenceIndex + direction * hs + 8) % 8;
    driveCurrentStep();
    stepPosition += direction * hs;

    if (remainingSteps > 0 && --remainingSteps == 0) {
      stopMotor("Movimiento completado");
    }
  }
  delay(1);
}
