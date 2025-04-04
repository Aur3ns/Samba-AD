#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARDED_LOG="/var/log/clamav/clamd-forwarding.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# === Début du scan ===
echo "[$TIMESTAMP] WARNING: ClamAV scan started." | tee -a "$LOGFILE" "$FORWARDED_LOG"

# === Scan avec clamdscan ===
ionice -c3 -n7 nice -n19 clamdscan -r --multiscan --fdpass / >> "$LOGFILE" 2>&1

# === Infections détectées ===
grep "FOUND" "$LOGFILE" | while IFS=: read -r filepath _ virus; do
  echo "[$TIMESTAMP] $filepath:$virus FOUND" | tee -a "$LOGFILE" "$FORWARDED_LOG"

  if [ -f "$filepath" ]; then
    rm -f "$filepath"
    echo "[$TIMESTAMP] $filepath:$virus REMOVED" | tee -a "$LOGFILE" "$FORWARDED_LOG"
  else
    echo "[$TIMESTAMP] $filepath:$virus ERROR" | tee -a "$LOGFILE" "$FORWARDED_LOG"
  fi
done

# === Fin du scan ===
echo "[$TIMESTAMP] WARNING: ClamAV scan completed." | tee -a "$LOGFILE" "$FORWARDED_LOG"
