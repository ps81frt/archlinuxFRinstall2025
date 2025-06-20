#!/bin/bash

# Script de partitionnement GPT UEFI pour Arch Linux
# Disque: 250Go
# sda1: 1Go EFI
# sda2: 4Go SWAP
# sda3: 50Go ROOT
# sda4: 100Go HOME
# sda5: Reste (environ 95Go)

set -e  # Arrêter le script en cas d'erreur

DISK="/dev/sda"

echo "=== Script de partitionnement GPT UEFI pour Arch Linux ==="
echo "Disque cible: $DISK"
echo ""
echo "ATTENTION: Ce script va EFFACER TOUTES LES DONNÉES du disque $DISK"
echo "Partitions qui seront créées:"
echo "  sda1: 1Go   - EFI System Partition"
echo "  sda2: 4Go   - Linux Swap"
echo "  sda3: 50Go  - Linux Root (/)"
echo "  sda4: 100Go - Linux Home (/home)"
echo "  sda5: ~95Go - Partition supplémentaire"
echo ""

read -p "Êtes-vous sûr de vouloir continuer? (oui/non): " confirmation
if [[ $confirmation != "oui" ]]; then
    echo "Opération annulée."
    exit 1
fi

# Vérifier que le disque existe
if [[ ! -b $DISK ]]; then
    echo "Erreur: Le disque $DISK n'existe pas!"
    exit 1
fi

# Vérifier que sgdisk est installé
if ! command -v sgdisk &> /dev/null; then
    echo "Erreur: sgdisk n'est pas installé. Installez gptfdisk:"
    echo "sudo pacman -S gptfdisk"
    exit 1
fi

echo "Démontage des partitions existantes..."
umount ${DISK}* 2>/dev/null || true

echo "Effacement de la table de partition existante..."
sgdisk --zap-all $DISK

echo "Création de la nouvelle table de partition GPT..."

# Créer les partitions avec sgdisk
echo "Création de sda1 (EFI System Partition - 1Go)..."
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:"EFI System" $DISK

echo "Création de sda2 (Linux Swap - 4Go)..."
sgdisk --new=2:0:+4G --typecode=2:8200 --change-name=2:"Linux Swap" $DISK

echo "Création de sda3 (Linux Root - 50Go)..."
sgdisk --new=3:0:+50G --typecode=3:8300 --change-name=3:"Linux Root" $DISK

echo "Création de sda4 (Linux Home - 100Go)..."
sgdisk --new=4:0:+100G --typecode=4:8300 --change-name=4:"Linux Home" $DISK

echo "Création de sda5 (Partition supplémentaire - reste de l'espace)..."
sgdisk --new=5:0:0 --typecode=5:8300 --change-name=5:"Linux Data" $DISK

echo "Vérification de la table de partition..."
sgdisk --print $DISK

echo ""
echo "Formatage des partitions..."

echo "Formatage de sda1 en FAT32 (EFI)..."
mkfs.fat -F32 -n "EFI" ${DISK}1

echo "Création du swap sur sda2..."
mkswap -L "SWAP" ${DISK}2

echo "Formatage de sda3 en ext4 (Root)..."
mkfs.ext4 -L "ROOT" ${DISK}3

echo "Formatage de sda4 en ext4 (Home)..."
mkfs.ext4 -L "HOME" ${DISK}4

echo "Formatage de sda5 en ext4 (Data)..."
mkfs.ext4 -L "DATA" ${DISK}5

echo ""
echo "=== PARTITIONNEMENT TERMINÉ ==="
echo "Table de partition finale:"
lsblk $DISK

echo ""
echo "Pour monter les partitions pour l'installation d'Arch Linux:"
echo "mount ${DISK}3 /mnt"
echo "mkdir -p /mnt/{boot,home,data}"
echo "mount ${DISK}1 /mnt/boot"
echo "mount ${DISK}4 /mnt/home"
echo "mount ${DISK}5 /mnt/data"
echo "swapon ${DISK}2"

echo ""
echo "Script terminé avec succès!"