#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARD_LOG="/var/log/clamav/clamd-forwarding.log"

# === Lancer le scan avec clamdscan ===
clamdscan -r --multiscan --fdpass /tmp >> "$LOGFILE" 2>/dev/null

# === Rechercher les fichiers infectés ===
grep "FOUND" "$LOGFILE" | cut -d: -f1 | while read -r file; do
  if [ -f "$file" ]; then
    rm -f "$file"
  fi
done

# === Forward log à Wazuh ===
grep "FOUND" "$LOGFILE" >> "$FORWARD_LOG"
