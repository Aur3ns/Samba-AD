#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARDED_LOG="/var/log/clamav/clamd-forwarding.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] [★] Beginning of the ClamAV scan..." >> "$LOGFILE"

# === Scan complet avec clamdscan ===
ionice -c3 -n7 nice -n19 clamdscan -r --multiscan --fdpass /tmp >> "$LOGFILE" 2>&1

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] [✓] Scan Completed. Checking infected files..." >> "$LOGFILE"

# === Rediriger les infections et suppressions vers le log lu par Wazuh ===
grep -E 'FOUND|ClamAv: Removed' "$LOGFILE" >> "$FORWARDED_LOG"

# === Suppression des fichiers infectés ===
grep -E '^[^:]+: .*FOUND$' "$LOGFILE" | cut -d: -f1 | while read -r file; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  if [ -f "$file" ]; then
    echo "[$TIMESTAMP] ClamAv: Removed : $file" | tee -a "$LOGFILE" >> "$FORWARDED_LOG"
    rm -f "$file"
  else
    echo "[$TIMESTAMP] [?] ClamAv Error: File not found : $file" >> "$LOGFILE"
  fi
done

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] [✓] ClamAv Deletion completed" >> "$LOGFILE"
