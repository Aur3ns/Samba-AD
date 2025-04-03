#!/bin/bash

# === Paramètres ===
LOGFILE="/var/log/clamav/clamdscan.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] [*] Début du scan ClamAV..." >> "$LOGFILE"

# === Scan complet avec clamdscan ===
ionice -c3 -n7 nice -n19 clamdscan -r --multiscan --fdpass / >> "$LOGFILE" 2>&1

echo "[$TIMESTAMP] [*] Scan terminé. Vérification des fichiers infectés..." >> "$LOGFILE"

# === Rediriger les infections vers le log lu par Wazuh ===
grep FOUND "$LOGFILE" >> /var/log/clamav/clamd.log

# === Suppression des fichiers infectés ===
grep FOUND "$LOGFILE" | cut -d: -f1 | while read -r file; do
  if [ -f "$file" ]; then
    echo "[$TIMESTAMP] [-] Suppression : $file" >> "$LOGFILE"
    rm -f "$file"
  else
    echo "[$TIMESTAMP] [?] Fichier introuvable : $file" >> "$LOGFILE"
  fi
done

echo "[$TIMESTAMP] [✓] Suppression terminée." >> "$LOGFILE"
