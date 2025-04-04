#!/bin/bash

# === Fichiers de log ===
LOGFILE="/var/log/clamav/clamdscan.log"
FORWARD_LOG="/var/log/clamav/clamd-forwarding.log"

# === Scan silencieux ===
clamdscan -r --multiscan --fdpass /tmp >> "$LOGFILE" 2>&1

# === Extraire les fichiers infectés ===
grep FOUND "$LOGFILE" | while IFS= read -r line; do
    echo "$line" >> "$FORWARD_LOG"

    file_path=$(echo "$line" | cut -d: -f1)
    virus_name=$(echo "$line" | cut -d: -f2 | awk '{print $2}')

    if [ -f "$file_path" ]; then
        rm -f "$file_path"
        echo "$file_path: $virus_name REMOVED" >> "$FORWARD_LOG"
    else
        echo "$file_path: $virus_name ERROR" >> "$FORWARD_LOG"
    fi
done
