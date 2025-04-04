#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARD_LOG="/var/log/clamav/clamd-forwarding.log"

# === Lancer le scan avec clamdscan ===
clamdscan -r --multiscan --fdpass /tmp >> "$LOGFILE" 2>/dev/null

# === Rechercher les fichiers infectés ===
grep "FOUND" "$LOGFILE" | cut -d: -f1 | while read -r file; do
  if [ -f "$file" ]; then
    echo "$file: REMOVED" | tee -a "$LOGFILE" >> "$FORWARD_LOG"
    rm -f "$file"
  else
    echo "$file: FOUND ERROR" | tee -a "$LOGFILE" >> "$FORWARD_LOG"
  fi
done
