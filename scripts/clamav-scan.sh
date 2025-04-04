#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARD_LOG="/var/log/clamav/clamd-forwarding.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# === Démarrer le scan ===
echo "[$TIMESTAMP] WARNING: ClamAV scan started." | tee -a "$LOGFILE" "$FORWARD_LOG"
ionice -c3 -n7 nice -n19 clamdscan -r --multiscan --fdpass /tmp >> "$LOGFILE" 2>&1
echo "[$TIMESTAMP] WARNING: ClamAV scan completed." | tee -a "$LOGFILE" "$FORWARD_LOG"

# === Extraire les fichiers infectés ===
grep FOUND "$LOGFILE" | while IFS= read -r line; do
    file_path=$(echo "$line" | cut -d: -f1)
    virus_name=$(echo "$line" | cut -d: -f2 | awk '{print $2}')
    echo "[$TIMESTAMP] $file_path: $virus_name FOUND" | tee -a "$LOGFILE" "$FORWARD_LOG"

    if [ -f "$file_path" ]; then
        rm -f "$file_path"
        echo "[$TIMESTAMP] $file_path: $virus_name REMOVED" | tee -a "$LOGFILE" "$FORWARD_LOG"
    else
        echo "[$TIMESTAMP] $file_path: $virus_name ERROR" | tee -a "$LOGFILE" "$FORWARD_LOG"
    fi
done
