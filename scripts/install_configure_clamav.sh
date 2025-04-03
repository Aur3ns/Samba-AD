#!/bin/bash

echo "[*] Mise à jour des dépôts..."
apt update

echo "[*] Installation de ClamAV et du démon Freshclam..."
apt install -y clamav clamav-daemon

echo "[*] Arrêt du démon freshclam pour mise à jour manuelle..."
systemctl stop clamav-freshclam

echo "[*] Mise à jour de la base de définitions de virus..."
freshclam

echo "[*] Création des fichiers de log ClamAV..."
mkdir -p /var/log/clamav
touch /var/log/clamav/clamd.log
touch /var/log/clamav/analyse.log
chown clamav:clamav /var/log/clamav/*.log
chmod 640 /var/log/clamav/*.log

echo "[*] Configuration du démon ClamAV (clamd)..."
sed -i 's|^#LogFile .*|LogFile /var/log/clamav/clamd.log|' /etc/clamav/clamd.conf
sed -i 's|^#LogTime .*|LogTime yes|' /etc/clamav/clamd.conf
sed -i 's|^LogSyslog yes|LogSyslog no|' /etc/clamav/clamd.conf

echo "[*] Redémarrage des services ClamAV..."
systemctl enable clamav-freshclam
systemctl start clamav-freshclam
systemctl restart clamav-daemon

echo "[*] Création d'une tâche cron quotidienne à minuit pour scanner tout le système..."

cat <<EOF > /etc/cron.d/clamav-fullscan
0 0 * * * root ionice -c3 -n7 nice -n 19 clamscan -r -i / >> /var/log/clamav/analyse.log 2>/dev/null
EOF

chmod 644 /etc/cron.d/clamav-fullscan

echo "[✓] Installation terminée !"
echo "    ➤ ClamAV scannera TOUT le système chaque nuit à 00h00"
echo "    ➤ Les fichiers infectés seront enregistrés dans : /var/log/clamav/analyse.log"
