#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARD_LOG="/var/log/clamav/clamd-forwarding.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] [✳] Beginning of the ClamAV scan..." >> "$LOGFILE"

# === Scan complet avec clamdscan ===
ionice -c3 -n7 nice -n19 clamdscan -r --multiscan --fdpass /tmp >> "$LOGFILE" 2>&1

echo "[$TIMESTAMP] [✔] Scan Completed. Checking infected files..." >> "$LOGFILE"

# === Suppression des fichiers infectés (et log REMOVED pour Wazuh) ===
grep "FOUND" "$LOGFILE" | while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  if [ -f "$file" ]; then
    # Même format que FOUND mais avec REMOVED
    echo "$line" | sed 's/FOUND/REMOVED/' | tee -a "$LOGFILE" >> "$FORWARD_LOG"
    rm -f "$file"
  else
    echo "[$TIMESTAMP] [?] ClamAV Error: File not found : $file" >> "$LOGFILE"
  fi
done

echo "[$TIMESTAMP] [-] ClamAV Deletion completed" >> "$LOGFILE"
