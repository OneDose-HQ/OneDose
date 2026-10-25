// File: hardware/rfid_scanner.ino
// Owner: Bhavya  (only the owner edits this file)
// Purpose: ESP32 + RC522 card reader: read the card UID, hash it with a salt (SHA-256), POST it to the backend /scan with the device key, green or red LED, 2-second debounce. Wi-Fi name and password go in a local secrets.h that is never committed.
// Inputs: A card tap.
// Outputs: An HTTP POST to /scan.
// Depends on: backend POST /scan
//
// What is sent:  POST {BACKEND_URL}/scan   header X-Device-Key: DEVICE_KEY
//                body {"uid_hash": "<64 hex>", "device": "<DEVICE_NAME>"}
// The hash is SHA-256 of  "<UID in upper-case hex, no separators>::<CARD_SALT>".  The raw UID never leaves the reader.
// The backend answers 200 {"outcome": "...", "matched": true|false}. Green LED = matched, red LED = anything else.
//
// Libraries (Arduino IDE > Library Manager):  "MFRC522" by GithubCommunity (miguelbalboa).  WiFi, HTTPClient and
// mbedtls come with the ESP32 board package.  Board: "ESP32 Dev Module".
//
// Wiring (ESP32 DevKit, hardware SPI)          RC522 pin -> ESP32 pin
//   SDA (SS)  -> GPIO 5        SCK  -> GPIO 18      MOSI -> GPIO 23      MISO -> GPIO 19
//   RST       -> GPIO 22       3.3V -> 3V3 (NOT 5V, the RC522 is a 3.3 V part)      GND -> GND
//   Green LED: GPIO 26 -> 220 ohm resistor -> LED (+), LED (-) -> GND
//   Red LED:   GPIO 27 -> 220 ohm resistor -> LED (+), LED (-) -> GND
//
// First-time setup: copy secrets.h.example to secrets.h (same folder) and fill it in. secrets.h is in .gitignore.
// Registering a physical card: tap it, read the "UID" line in the Serial Monitor (115200 baud), then in psql run
//   UPDATE rfid_cards SET uid_hash = digest('<UID>::OneDoseDemoCardSalt2026', 'sha256') WHERE patient_id = <n>;
#include <SPI.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <MFRC522.h>
#include "mbedtls/sha256.h"
#include "secrets.h"   // WIFI_SSID, WIFI_PASSWORD, BACKEND_URL, DEVICE_KEY, DEVICE_NAME, CARD_SALT

const uint8_t PIN_SS = 5, PIN_RST = 22, PIN_GREEN = 26, PIN_RED = 27;
const unsigned long DEBOUNCE_MS = 2000;   // ignore every tap for 2 seconds after one is handled
const unsigned long LED_MS = 1200;        // how long the result LED stays on
const uint16_t HTTP_TIMEOUT_MS = 5000;

MFRC522 reader(PIN_SS, PIN_RST);
unsigned long lastTapAt = 0;
bool haveTapped = false;

void showResult(bool ok) {
  digitalWrite(ok ? PIN_GREEN : PIN_RED, HIGH);
  delay(LED_MS);
  digitalWrite(PIN_GREEN, LOW);
  digitalWrite(PIN_RED, LOW);
}

void blinkRed(int times) {
  for (int i = 0; i < times; i++) {
    digitalWrite(PIN_RED, HIGH); delay(150);
    digitalWrite(PIN_RED, LOW);  delay(150);
  }
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.print("Wi-Fi: connecting");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    digitalWrite(PIN_RED, !digitalRead(PIN_RED));   // slow red blink while connecting
    delay(300);
    Serial.print(".");
  }
  digitalWrite(PIN_RED, LOW);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print(" connected, IP ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println(" failed (will retry on the next tap)");
  }
}

// "04A1B2C3" from the raw UID bytes (upper-case, no separators)
String uidToHex(const MFRC522::Uid &uid) {
  String s;
  for (byte i = 0; i < uid.size; i++) {
    if (uid.uidByte[i] < 0x10) s += "0";
    s += String(uid.uidByte[i], HEX);
  }
  s.toUpperCase();
  return s;
}

// 64 lower-case hex characters: SHA-256 of "<uid>::<salt>"
String hashUid(const String &uidHex) {
  String input = uidHex + "::" + CARD_SALT;
  unsigned char digest[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  mbedtls_sha256_starts(&ctx, 0);   // 0 = SHA-256 (not SHA-224)
  mbedtls_sha256_update(&ctx, (const unsigned char *)input.c_str(), input.length());
  mbedtls_sha256_finish(&ctx, digest);
  mbedtls_sha256_free(&ctx);
  String hex;
  for (int i = 0; i < 32; i++) {
    if (digest[i] < 0x10) hex += "0";
    hex += String(digest[i], HEX);
  }
  return hex;
}

// Returns true only when the backend answered 200 and said matched:true.
bool postScan(const String &hash) {
  connectWifi();
  if (WiFi.status() != WL_CONNECTED) return false;

  String url = String(BACKEND_URL) + "/scan";
  String body = "{\"uid_hash\":\"" + hash + "\",\"device\":\"" + DEVICE_NAME + "\"}";

  HTTPClient http;
  WiFiClientSecure secure;
  WiFiClient plain;
  bool begun;
  if (url.startsWith("https://")) {
    // Prototype: the certificate is not pinned. For a real deployment call secure.setCACert(<root CA>) instead.
    secure.setInsecure();
    begun = http.begin(secure, url);
  } else {
    begun = http.begin(plain, url);
  }
  if (!begun) return false;

  http.setTimeout(HTTP_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Device-Key", DEVICE_KEY);
  int code = http.POST(body);
  String reply = (code > 0) ? http.getString() : String("");
  http.end();

  Serial.printf("POST /scan -> HTTP %d  %s\n", code, reply.c_str());
  return code == 200 && reply.indexOf("\"matched\":true") >= 0;
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_GREEN, OUTPUT);
  pinMode(PIN_RED, OUTPUT);
  digitalWrite(PIN_GREEN, LOW);
  digitalWrite(PIN_RED, LOW);

  SPI.begin();          // default ESP32 VSPI: SCK 18, MISO 19, MOSI 23
  reader.PCD_Init();
  byte version = reader.PCD_ReadRegister(MFRC522::VersionReg);
  Serial.printf("RC522 firmware version 0x%02X %s\n", version,
                (version == 0x00 || version == 0xFF) ? "(NOT DETECTED - check wiring)" : "(ok)");
  if (version == 0x00 || version == 0xFF) blinkRed(5);

  connectWifi();
  Serial.println("Ready. Tap a card.");
}

void loop() {
  if (haveTapped && millis() - lastTapAt < DEBOUNCE_MS) {
    // inside the debounce window: swallow the card so a held card is not read again
    if (reader.PICC_IsNewCardPresent()) { reader.PICC_ReadCardSerial(); reader.PICC_HaltA(); }
    return;
  }
  if (!reader.PICC_IsNewCardPresent() || !reader.PICC_ReadCardSerial()) return;

  lastTapAt = millis();
  haveTapped = true;

  String uidHex = uidToHex(reader.uid);
  reader.PICC_HaltA();
  reader.PCD_StopCrypto1();

  Serial.println("UID: " + uidHex);   // used only to register a card, never sent over the network
  bool ok = postScan(hashUid(uidHex));
  showResult(ok);
  lastTapAt = millis();   // start the debounce window after the LED, not before
}
