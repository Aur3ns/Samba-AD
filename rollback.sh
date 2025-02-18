#!/bin/bash

LOG_FILE="/var/log/samba-rollback.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Début du rollback de Samba et de la configuration de sécurité" | tee -a $LOG_FILE
echo "====================" | tee -a $LOG_FILE

### 1. Arrêt et désactivation des services ###
echo "[*] Arrêt et désactivation des services Samba, Kerberos et autres..." | tee -a $LOG_FILE
systemctl stop samba-ad-dc
systemctl disable samba-ad-dc
systemctl stop fail2ban
systemctl disable fail2ban
systemctl stop auditd
systemctl disable auditd
systemctl stop osqueryd
systemctl disable osqueryd
systemctl stop chrony
systemctl disable chrony
systemctl restart sshd
systemctl stop krb5-admin-server
systemctl disable krb5-admin-server
systemctl stop krb5-kdc
systemctl disable krb5-kdc

### 2. Suppression de la configuration Samba et Kerberos ###
echo "[*] Suppression des fichiers de configuration Samba et Kerberos..." | tee -a $LOG_FILE
rm -rf /etc/samba
rm -rf /var/lib/samba
rm -rf /var/log/samba
rm -rf /etc/krb5.conf
rm -rf /var/lib/krb5kdc
rm -rf /etc/krb5kdc

### 3. Suppression des certificats TLS ###
echo "[*] Suppression des certificats TLS générés..." | tee -a $LOG_FILE
rm -rf /etc/samba/private/tls*

### 4. Suppression des unités d'organisation et des groupes ###
echo "[*] Suppression des unités d'organisation (OU) et des groupes Samba..." | tee -a $LOG_FILE
OU_LIST=("OU=NS,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT0,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT1,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT2,DC=northstar,DC=com"
    "OU=NS,OU=Servers_T1,DC=northstar,DC=com"
    "OU=NS,OU=AdminWorkstations,DC=northstar,DC=com")

for OU in "${OU_LIST[@]}"; do
    samba-tool ou delete "$OU" | tee -a $LOG_FILE
done

GROUPS=("Group_ADMT0" "Group_ADMT1" "Group_ADMT2")
for GROUP in "${GROUPS[@]}"; do
    samba-tool group delete "$GROUP" | tee -a $LOG_FILE
done

### 5. Suppression des utilisateurs créés ###
echo "[*] Suppression des utilisateurs Samba..." | tee -a $LOG_FILE
samba-tool user delete Hugo_ADMT0 | tee -a $LOG_FILE
samba-tool user delete Voltaire_ADMT1 | tee -a $LOG_FILE
samba-tool user delete Clemenceau_ADMT2 | tee -a $LOG_FILE

### 6. Restauration de la configuration SSH ###
echo "[*] Restauration de la configuration SSH..." | tee -a $LOG_FILE
cp /etc/ssh/sshd_config.orig /etc/ssh/sshd_config 2>/dev/null
systemctl restart sshd

### 7. Suppression des règles Fail2Ban ###
echo "[*] Suppression des règles Fail2Ban..." | tee -a $LOG_FILE
rm -rf /etc/fail2ban/jail.d/samba.conf
rm -rf /etc/fail2ban/filter.d/samba.conf
systemctl restart fail2ban

### 8. Suppression des règles auditd ###
echo "[*] Suppression des règles auditd..." | tee -a $LOG_FILE
rm -rf /etc/audit/rules.d/audit.rules
systemctl restart auditd

### 9. Restauration des permissions des fichiers système ###
echo "[*] Restauration des permissions des fichiers critiques..." | tee -a $LOG_FILE
chmod 644 /etc/passwd /etc/group
chmod 640 /etc/shadow /etc/gshadow

### 10. Suppression des modifications sysctl ###
echo "[*] Suppression des modifications sysctl..." | tee -a $LOG_FILE
rm -rf /etc/sysctl.d/99-hardening.conf
sysctl --system

### 11. Suppression des entrées FSTAB ###
echo "[*] Suppression des entrées de sécurisation des partitions..." | tee -a $LOG_FILE
sed -i '/\/tmp/d' /etc/fstab
sed -i '/\/var/d' /etc/fstab
mount -o remount /tmp
mount -o remount /var

### 12. Suppression des modifications PAM ###
echo "[*] Suppression des modifications PAM..." | tee -a $LOG_FILE
sed -i '/minlen = 14/d' /etc/security/pwquality.conf
sed -i '/minclass = 4/d' /etc/security/pwquality.conf
sed -i '/retry = 3/d' /etc/security/pwquality.conf

### 13. Suppression des fichiers générés ###
echo "[*] Suppression des fichiers temporaires générés..." | tee -a $LOG_FILE
rm -f /root/northstar_users.txt
rm -f /root/northstar.ldif
rm -f /var/log/samba-setup.log

### 14. Suppression des fichiers de configuration osquery ###
echo "[*] Suppression des fichiers de configuration osquery..." | tee -a $LOG_FILE
rm -rf /etc/osquery
systemctl restart osqueryd

### 15. Nettoyage final ###
echo "[*] Nettoyage du système..." | tee -a $LOG_FILE
apt autoremove -y
apt autoclean -y

echo "$(date '+%Y-%m-%d %H:%M:%S') - Rollback terminé !" | tee -a $LOG_FILE
echo "====================" | tee -a $LOG_FILE
