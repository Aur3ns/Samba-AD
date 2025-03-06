#!/bin/bash

LOG_FILE="/var/log/chrony_setup.log"
CHRONY_CONF="/etc/chrony/chrony.conf"
NTP_SUBNET="10.10.0.0/24"  # ⚠️ À adapter à ton réseau

# Fonction de log
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log "========================================="
log "⏰ Début de la configuration de Chrony..."
log "========================================="

# 1. Installation de Chrony si non installé
if ! command -v chronyd &>/dev/null; then
    log "📦 Installation de Chrony..."
    if [[ -f /etc/debian_version ]]; then
        apt update && apt install chrony -y
    elif [[ -f /etc/redhat-release ]]; then
        yum install chrony -y
    elif [[ -f /etc/arch-release ]]; then
        pacman -S chrony --noconfirm
    else
        log "❌ Distribution non prise en charge."
        exit 1
    fi
else
    log "✅ Chrony est déjà installé."
fi

# 2. Sauvegarde de l'ancienne configuration
if [ -f "$CHRONY_CONF" ]; then
    log "📂 Sauvegarde de l'ancienne configuration : ${CHRONY_CONF}.bak"
    cp "$CHRONY_CONF" "${CHRONY_CONF}.bak"
fi

# 3. Configuration de Chrony
log "📝 Configuration de Chrony..."
cat <<EOF > "$CHRONY_CONF"
# Serveurs NTP publics pour la synchronisation
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst

# Autoriser les clients internes à interroger le serveur
allow $NTP_SUBNET

# Ce serveur est une référence de temps fiable
local stratum 10

# Ajustement de l'horloge
makestep 1.0 3
rtcsync

# Fichier de drift
driftfile /var/lib/chrony/drift
EOF

# 4. Ouverture du port 123/UDP dans le pare-feu
log "🔓 Ouverture du port NTP (123/UDP) dans le pare-feu..."
if command -v ufw &>/dev/null; then
    ufw allow 123/udp
    ufw reload
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=ntp
    firewall-cmd --reload
elif command -v iptables &>/dev/null; then
    iptables -A INPUT -p udp --dport 123 -j ACCEPT
else
    log "⚠️ Aucun pare-feu détecté, vérification manuelle requise."
fi

# 5. Redémarrage de Chrony
log "🔄 Redémarrage du service Chrony..."
systemctl restart chronyd
systemctl enable chronyd

# 6. Vérification de l'état
log "🔍 Vérification des sources NTP..."
chronyc sources -v | tee -a "$LOG_FILE"

log "========================================="
log "✅ Configuration de Chrony terminée !"
log "========================================="
