#!/bin/bash

# Vérifie si le script est exécuté avec les privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en tant que root."
  exit 1
fi

echo "Modification des paramètres régionaux pour Debian..."

# Change la configuration des locales pour que les messages système restent en français
sed -i '/^LANG=/c\LANG=fr_FR.UTF-8' /etc/default/locale
sed -i '/^LANGUAGE=/c\LANGUAGE=fr_FR:fr' /etc/default/locale
grep -q "^LC_MESSAGES=" /etc/default/locale || echo "LC_MESSAGES=fr_FR.UTF-8" >> /etc/default/locale

# Force les noms des dossiers utilisateurs à passer en anglais
echo "en_US" > ~/.config/user-dirs.locale

# Met à jour les noms des dossiers utilisateurs
echo "Modification des noms de dossiers utilisateurs en anglais..."
LANG=en_US xdg-user-dirs-update --force

echo "Opération terminée. Veuillez redémarrer votre session pour appliquer les changements."
