#!/bin/bash

# Vérifie si le script est exécuté avec les privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en tant que root."
  exit 1
fi

echo "Modification des paramètres régionaux pour Debian..."

# Change la configuration des locales
sed -i 's/^LANG=.*/LANG=fr_FR.UTF-8/' /etc/default/locale
sed -i 's/^LANGUAGE=.*/LANGUAGE=fr_FR:fr/' /etc/default/locale
echo "LC_MESSAGES=fr_FR.UTF-8" >> /etc/default/locale

# Applique les modifications pour l'utilisateur actuel
export LANG=fr_FR.UTF-8
export LANGUAGE=fr_FR:fr
export LC_MESSAGES=fr_FR.UTF-8

# Remet les noms des dossiers utilisateurs en anglais
echo "Modification des noms de dossiers utilisateurs en anglais..."
LANG=C xdg-user-dirs-update --force

echo "Opération terminée. Veuillez redémarrer votre session pour appliquer les changements."

