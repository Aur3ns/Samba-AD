#!/bin/bash
# Ce script demande le mot de passe une seule fois, obtient un ticket Kerberos,
# et met à jour les ACL de toutes les GPOs pour qu'elles s'appliquent uniquement aux ordinateurs.

# Variables de domaine
DOMAIN="northstar.com"
DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
ADMIN_USER="Administrator"  # Adaptez si besoin

# Demande du mot de passe (il ne sera affiché aucun caractère)
read -rsp "Entrez le mot de passe pour kinit ($ADMIN_USER@$DOMAIN_UPPER) : " PASS
echo

# Obtention du ticket Kerberos
echo "$PASS" | kinit "$ADMIN_USER@$DOMAIN_UPPER"
if [ $? -ne 0 ]; then
    echo "Erreur : kinit a échoué ! Vérifiez vos identifiants."
    exit 1
fi
echo "Ticket Kerberos obtenu avec succès."

# Mise à jour des ACL pour chaque GPO
echo "Mise à jour des ACL pour les GPOs..."

# Disable_CMD
samba-tool gpo setacl "Disable_CMD" --remove "NT AUTHORITY\Authenticated Users:AP" --use-kerberos=required
samba-tool gpo setacl "Disable_CMD" --add "${DOMAIN_UPPER}\Domain Computers:RP,AP" --use-kerberos=required

# Force_SMB_Encryption
samba-tool gpo setacl "Force_SMB_Encryption" --remove "NT AUTHORITY\Authenticated Users:AP" --use-kerberos=required
samba-tool gpo setacl "Force_SMB_Encryption" --add "${DOMAIN_UPPER}\Domain Computers:RP,AP" --use-kerberos=required

# Block_Temp_Executables
samba-tool gpo setacl "Block_Temp_Executables" --remove "NT AUTHORITY\Authenticated Users:AP" --use-kerberos=required
samba-tool gpo setacl "Block_Temp_Executables" --add "${DOMAIN_UPPER}\Domain Computers:RP,AP" --use-kerberos=required

# Disable_Telemetry
samba-tool gpo setacl "Disable_Telemetry" --remove "NT AUTHORITY\Authenticated Users:AP" --use-kerberos=required
samba-tool gpo setacl "Disable_Telemetry" --add "${DOMAIN_UPPER}\Domain Computers:RP,AP" --use-kerberos=required

# NTP_Sync
samba-tool gpo setacl "NTP_Sync" --remove "NT AUTHORITY\Authenticated Users:AP" --use-kerberos=required
samba-tool gpo setacl "NTP_Sync" --add "${DOMAIN_UPPER}\Domain Computers:RP,AP" --use-kerberos=required

# Security_Message
samba-tool gpo setacl "Security_Message" --remove "NT AUTHORITY\Authenticated Users:AP" --use-kerberos=required
samba-tool gpo setacl "Security_Message" --add "${DOMAIN_UPPER}\Domain Computers:RP,AP" --use-kerberos=required

echo "ACL mises à jour pour toutes les GPOs."
