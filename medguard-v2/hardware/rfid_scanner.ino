// File: hardware/rfid_scanner.ino
// Owner: Bhavya  (only the owner edits this file)
// Purpose: ESP32 + RC522 card reader: read the card UID, hash it with a salt (SHA-256), POST it to the backend /scan with the device key, green or red LED, 2-second debounce. Wi-Fi name and password go in a local secrets.h that is never committed.
// Inputs: A card tap.
// Outputs: An HTTP POST to /scan.
// Depends on: backend POST /scan
