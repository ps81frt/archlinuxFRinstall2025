#!/bin/bash
# V52
set -e

#=== Couleurs ===
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
NC='\e[0m'

#=== Fonction pour poser une question ===
ask() {
  local prompt="$1"
  read -rp "$prompt: " response
  echo "$response"
}

#=== Détecter mode BIOS ou UEFI ===
detect_boot_mode() {
  if [ -d /sys/firmware/efi ]; then
    echo "UEFI"
  else
    echo "BIOS"
  fi
}

#=== Choisir le disque ===
choose_disk() {
  echo -e "${BLUE}=== Disques disponibles ===${NC}"
  local disks=()
  local i=1
  while IFS= read -r line; do
    disks+=("$line")
    echo "[$i] $line"
    ((i++))
  done < <(lsblk -dpno NAME,SIZE | grep -v "/loop")

  echo
  local choice
  while true; do
    choice=$(ask "Choisissez un disque (numéro)")
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#disks[@]} ]; then
      local disk_name
      disk_name=$(echo "${disks[$((choice - 1))]}" | awk '{print $1}')
      echo "$disk_name"
      return
    else
      echo -e "${RED}Choix invalide.${NC}"
    fi
  done
}

#=== Créer table de partition ===
partition_disk() {
  local disk="$1"
  local boot_mode="$2"

  echo -e "${YELLOW}Nettoyage des anciennes partitions sur $disk...${NC}"
  wipefs -a "$disk"

  echo -e "${BLUE}Création de la table de partitions (${boot_mode})...${NC}"
  if [ "$boot_mode" == "UEFI" ]; then
    parted -s "$disk" mklabel gpt
  else
    parted -s "$disk" mklabel msdos
  fi
  echo -e "${GREEN}Table de partition créée avec succès.${NC}"
}

#=== Afficher et confirmer les étapes ===
main() {
  echo -e "${BLUE}=== Script de partitionnement automatique ===${NC}"

  local boot_mode
  boot_mode=$(detect_boot_mode)
  echo -e "${YELLOW}Mode de démarrage détecté : ${boot_mode}${NC}"

  local disk
  disk=$(choose_disk)
  echo -e "${YELLOW}Disque sélectionné : ${disk}${NC}"

  echo
  read -rp "\nToutes les données sur $disk seront PERDUES. Continuer ? (o/N): " confirm
  [[ "$confirm" =~ ^[oO]$ ]] || { echo -e "${RED}Annulation.${NC}"; exit 1; }

  partition_disk "$disk" "$boot_mode"

  echo -e "${GREEN}Opération terminée avec succès.${NC}"
  echo -e "${YELLOW}Vous pouvez maintenant créer les partitions manuellement ou automatiser cette étape.${NC}"
}

main
