#!/bin/bash

# Vérifie si le script est exécuté avec les privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en tant que root."
  exit 1
fi

echo "Modification des paramètres régionaux pour Debian..."

# Change la configuration des locales
sed -i '/^LANG=/c\LANG=fr_FR.UTF-8' /etc/default/locale
sed -i '/^LANGUAGE=/c\LANGUAGE=fr_FR:fr' /etc/default/locale
grep -q "^LC_MESSAGES=" /etc/default/locale || echo "LC_MESSAGES=fr_FR.UTF-8" >> /etc/default/locale

# Remplace la locale des dossiers utilisateurs par "en_US"
echo "en_US" > ~/.config/user-dirs.locale

# Remet les noms des dossiers utilisateurs en anglais
echo "Modification des noms de dossiers utilisateurs en anglais..."
LANG=C xdg-user-dirs-update --force

echo "Opération terminée. Veuillez redémarrer votre session pour appliquer les changements."
