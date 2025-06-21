#!/bin/bash
set -euo pipefail

echo "Lancement du script d'installation ArchLinuxFR 2025"

# Vérification des dépendances minimales
for cmd in curl lsblk parted pacstrap; do
  if ! command -v "$cmd" >/dev/null; then
    echo "Erreur : la commande '$cmd' est manquante."
    exit 1
  fi
done

# Vérification de la connexion Internet
if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
  echo "Pas de connexion Internet détectée."
  exit 1
fi

# Affichage du menu principal
echo ""
echo "Choisis ton mode d'installation :"
select choix in "Installation automatique" "Installation avancée" "Installation manuelle" "Quitter"; do
  case $REPLY in
    1)
      echo "Lancement de l'installation automatique..."
      curl -sL https://raw.githubusercontent.com/ps81frt/archlinuxFRinstall2025/main/autopartarchlinux.sh | bash
      break
      ;;
    2)
      echo "Lancement de l'installation avancée..."
      curl -sL https://raw.githubusercontent.com/ps81frt/archlinuxFRinstall2025/main/autopartarchlinuxadvanced.sh | bash
      break
      ;;
    3)
      echo "Lancement de l'installation manuelle guidée..."
      curl -sL https://raw.githubusercontent.com/ps81frt/archlinuxFRinstall2025/main/archinstall2025cli.sh | bash
      break
      ;;
    4)
      echo "Installation annulée."
      exit 0
      ;;
    *)
      echo "Choix invalide."
      ;;
  esac
done
