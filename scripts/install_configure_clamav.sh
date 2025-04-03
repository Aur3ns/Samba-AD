#!/bin/bash

echo "[*] Mise à jour des dépôts..."
apt update

echo "[*] Installation de ClamAV et du démon clamd..."
apt install -y clamav clamav-daemon rsyslog

echo "[*] Création du fichier de log clamd..."
mkdir -p /var/log/clamav
touch /var/log/clamav/clamd.log
chown clamav:clamav /var/log/clamav/clamd.log
chmod 640 /var/log/clamav/clamd.log

echo "[*] Configuration de clamd pour utiliser le fichier de log..."
sed -i 's|^#LogFile .*|LogFile /var/log/clamav/clamd.log|' /etc/clamav/clamd.conf
sed -i 's|^LogSyslog yes|LogSyslog no|' /etc/clamav/clamd.conf
sed -i 's|^#LogTime .*|LogTime yes|' /etc/clamav/clamd.conf

echo "[*] Redémarrage du démon clamd..."
systemctl enable clamav-daemon
systemctl restart clamav-daemon

echo "[*] Configuration de rsyslog pour surveiller les logs ClamAV..."
cat <<EOF > /etc/rsyslog.d/20-clamav.conf
module(load="imfile" PollingInterval="10")

input(type="imfile"
      File="/var/log/clamav/clamd.log"
      Tag="clamav:"
      Severity="info"
      Facility="local6")

local6.* /var/log/syslog
EOF

echo "[*] Redémarrage de rsyslog..."
systemctl restart rsyslog

echo "[*] Création de la tâche cron quotidienne (clamdscan)..."
cat <<EOF > /etc/cron.d/clamav-fullscan
0 0 * * * root ionice -c3 -n7 nice -n19 clamdscan --infected --multiscan --fdpass --remove=yes / > /dev/null 2>&1
EOF

chmod 644 /etc/cron.d/clamav-fullscan

echo "[✓] ClamAV (clamd) est installé, configuré, et intégré pour Wazuh 🎉"
echo "    ➤ Un scan complet du système sera lancé chaque nuit à minuit"
echo "    ➤ Les détections seront visibles dans /var/log/clamav/clamd.log"
echo "    ➤ Et automatiquement transmises à Wazuh via rsyslog + syslog"
