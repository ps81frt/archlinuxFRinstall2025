#!/bin/bash
set -euo pipefail
# V47
# Fonction debug
debug() {
  echo -e "\e[34m[DEBUG]\e[0m $*"
}

# Affiche un message d’erreur et quitte
error_exit() {
  echo -e "\e[31m[ERREUR]\e[0m $*"
  exit 1
}

# Affiche un menu whiptail pour choisir un disque
choose_disk() {
  local disks parts disk choice

  debug "Liste des disques disponibles"
  mapfile -t disks < <(lsblk -dno NAME,SIZE,MODEL | grep -v "rom" | awk '{print "/dev/"$1,$2,$3}')

  if [[ ${#disks[@]} -eq 0 ]]; then
    error_exit "Aucun disque trouvé"
  fi

  # Prépare options whiptail (alternance tag description)
  local options=()
  for d in "${disks[@]}"; do
    local dev size model
    read -r dev size model <<< "$d"
    options+=("$dev" "$size - $model")
  done

  debug "Ouverture menu choix disque"
  choice=$(whiptail --title "Choix du disque" --menu "Sélectionnez le disque cible:" 15 60 6 "${options[@]}" 3>&1 1>&2 2>&3) || error_exit "Abandon du choix disque"

  echo "$choice"
}

# Affiche un menu whiptail pour choisir une partition sur un disque donné
choose_partition() {
  local disk=$1 parts choice

  debug "Liste des partitions pour $disk"
  mapfile -t parts < <(lsblk -no NAME,SIZE,TYPE,MOUNTPOINT "$disk" | grep part | awk '{mp=$4; if(mp=="") mp="non monté"; print "/dev/"$1,$2,mp}')

  if [[ ${#parts[@]} -eq 0 ]]; then
    error_exit "Aucune partition sur $disk"
  fi

  local options=()
  for p in "${parts[@]}"; do
    local dev size mp
    read -r dev size mp <<< "$p"
    options+=("$dev" "$size - $mp")
  done

  debug "Ouverture menu choix partition"
  choice=$(whiptail --title "Choix de la partition racine" --menu "Sélectionnez la partition racine:" 15 70 8 "${options[@]}" 3>&1 1>&2 2>&3) || error_exit "Abandon du choix partition"

  echo "$choice"
}

# Formate la partition choisie en ext4
format_partition() {
  local part=$1
  debug "Formatage de la partition $part en ext4"
  mkfs.ext4 -F "$part" || error_exit "Erreur formatage $part"
  echo "Formatage de $part terminé."
}

# Monte la partition racine
mount_partition() {
  local part=$1
  debug "Montage de $part sur /mnt"
  mount "$part" /mnt || error_exit "Erreur montage $part"
  echo "Montage de $part sur /mnt réussi."
}

# Installe le système de base
install_base() {
  debug "Installation du système de base (base, linux, linux-firmware)"
  pacstrap /mnt base linux linux-firmware || error_exit "Erreur installation base"
  echo "Installation de base terminée."
}

# Génère fstab
gen_fstab() {
  debug "Génération de /etc/fstab"
  genfstab -U /mnt >> /mnt/etc/fstab || error_exit "Erreur génération fstab"
  echo "fstab généré."
}

# Installation minimale avec menu interactif

clear
echo "Bienvenue dans le script d'installation Arch Linux simplifié."

DISK=$(choose_disk)
echo "Disque sélectionné : $DISK"

PART=$(choose_partition "$DISK")
echo "Partition racine sélectionnée : $PART"

whiptail --yesno "Voulez-vous formater la partition $PART en ext4 ? Toutes les données seront perdues !" 10 60
if [[ $? -eq 0 ]]; then
  format_partition "$PART"
else
  echo "Formatage annulé, utilisation de la partition telle quelle."
fi

mount_partition "$PART"

install_base

gen_fstab

echo -e "\nInstallation terminée. Vous pouvez maintenant chrooter dans /mnt pour continuer la configuration."

exit 0
