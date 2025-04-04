#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARDED_LOG="/var/log/clamav/clamd-forwarding.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# === Début du scan ===
echo "[$TIMESTAMP] WARNING: ClamAV scan started." >> "$LOGFILE"
echo "[$TIMESTAMP] WARNING: ClamAV scan started." >> "$FORWARDED_LOG"

# === Scan avec clamdscan (mode silencieux) ===
SCAN_TEMP=$(mktemp)
/usr/bin/ionice -c3 -n7 /usr/bin/nice -n19 clamdscan -r --multiscan --fdpass / > "$SCAN_TEMP" 2>/dev/null

# === Infections détectées ===
grep "FOUND" "$SCAN_TEMP" | while IFS=: read -r filepath virusinfo; do
  virus=$(echo "$virusinfo" | grep -oP '[^ ]+(?= FOUND)')
  echo "[$TIMESTAMP] $filepath: $virus FOUND" >> "$LOGFILE"
  echo "[$TIMESTAMP] $filepath: $virus FOUND" >> "$FORWARDED_LOG"

  if [ -f "$filepath" ]; then
    rm -f "$filepath"
    echo "[$TIMESTAMP] $filepath: $virus REMOVED" >> "$LOGFILE"
    echo "[$TIMESTAMP] $filepath: $virus REMOVED" >> "$FORWARDED_LOG"
  else
    echo "[$TIMESTAMP] $filepath: $virus ERROR" >> "$LOGFILE"
    echo "[$TIMESTAMP] $filepath: $virus ERROR" >> "$FORWARDED_LOG"
  fi
done

# Nettoyage
rm -f "$SCAN_TEMP"

# === Fin du scan ===
TIMESTAMP_END=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP_END] WARNING: ClamAV scan completed." >> "$LOGFILE"
echo "[$TIMESTAMP_END] WARNING: ClamAV scan completed." >> "$FORWARDED_LOG"
