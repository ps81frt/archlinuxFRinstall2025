#!/bin/bash

set -e

# Fonction pour vérifier si une partition est montée
is_mounted() {
  mountpoint -q "$1"
}

# Vérifier que le script est lancé en root
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être lancé en root !" >&2
  exit 1
fi

# Vérification de la connexion Internet
echo "Vérification de la connexion Internet..."
ping -c 2 archlinux.org > /dev/null 2>&1 || { echo "Pas de connexion Internet détectée."; exit 1; }
echo "Connexion Internet OK."

# Liste des disques disponibles
echo "Disques disponibles :"
lsblk -d -o NAME,SIZE,MODEL

# Demander la partition racine
read -rp "Entrez la partition racine (ex : /dev/sda2) : " root_partition

# Vérifier si la partition existe
if ! lsblk "$root_partition" > /dev/null 2>&1; then
  echo "La partition $root_partition n'existe pas." >&2
  exit 1
fi

# Monter la partition racine
if is_mounted /mnt; then
  echo "/mnt est déjà monté."
else
  mount "$root_partition" /mnt || { echo "Erreur : impossible de monter $root_partition"; exit 1; }
fi

# Demander si une partition boot est utilisée
read -rp "Avez-vous une partition boot séparée ? (oui/non) : " boot_sep
if [[ "$boot_sep" =~ ^(oui|o|OUI|Oui)$ ]]; then
  read -rp "Entrez la partition boot (ex : /dev/sda1) : " boot_partition
  if is_mounted /mnt/boot; then
    echo "/mnt/boot est déjà monté."
  else
    mkdir -p /mnt/boot
    mount "$boot_partition" /mnt/boot || { echo "Erreur : impossible de monter $boot_partition"; exit 1; }
  fi
fi

# Demander si une partition EFI est utilisée
read -rp "Avez-vous une partition EFI (système UEFI) ? (oui/non) : " efi_sep
if [[ "$efi_sep" =~ ^(oui|o|OUI|Oui)$ ]]; then
  read -rp "Entrez la partition EFI (ex : /dev/sda1) : " efi_partition
  if is_mounted /mnt/boot/efi; then
    echo "/mnt/boot/efi est déjà monté."
  else
    mkdir -p /mnt/boot/efi
    mount "$efi_partition" /mnt/boot/efi || { echo "Erreur : impossible de monter $efi_partition"; exit 1; }
  fi
fi

# Mise à jour des miroirs et installation de base
pacman -Sy --noconfirm archlinux-keyring
pacstrap /mnt base base-devel linux linux-firmware vim nano networkmanager

# Génération du fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot dans le nouveau système
arch-chroot /mnt /bin/bash <<EOF

# Configuration de base
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf

# Définir le nom de la machine
read -rp "Entrez le nom de votre machine : " hostname
echo "$hostname" > /etc/hostname
echo "127.0.0.1	localhost" > /etc/hosts
echo "::1		localhost" >> /etc/hosts
echo "127.0.1.1	$hostname.localdomain	$hostname" >> /etc/hosts

# Installer le bootloader selon la configuration (UEFI ou BIOS)
if [ -d /sys/firmware/efi/efivars ]; then
  bootctl install
  cat <<EOT > /boot/loader/loader.conf
default arch
timeout 3
editor 0
EOT

  cat <<EOT > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=$root_partition rw
EOT
else
  pacman -S --noconfirm grub
  grub-install --target=i386-pc "$root_partition"
  grub-mkconfig -o /boot/grub/grub.cfg
fi

# Demander l'utilisateur final
read -rp "Entrez le nom d'utilisateur à créer : " username
useradd -m -G wheel -s /bin/bash "$username"
echo "Définissez le mot de passe pour $username :"
passwd "$username"

# Autoriser sudo pour les utilisateurs wheel
pacman -S --noconfirm sudo
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Choix de l'environnement de bureau ou gestionnaire de fenêtres
echo "Choisissez l'environnement à installer :"
echo "1) i3"
echo "2) sway"
echo "3) hyprland"
read -rp "Entrez 1, 2 ou 3 : " env_choice

case $env_choice in
  1)
    pacman -S --noconfirm xorg xorg-xinit i3 i3status dmenu
    ;;
  2)
    pacman -S --noconfirm sway wayland xorg-xwayland
    ;;
  3)
    pacman -S --noconfirm hyprland wayland xorg-xwayland
    ;;
  *)
    echo "Choix invalide, rien d'installé."
    ;;
esac

echo "Installation terminée, vous pouvez redémarrer."

EOF

# Démontage des partitions
umount -R /mnt

echo "Script terminé avec succès."
