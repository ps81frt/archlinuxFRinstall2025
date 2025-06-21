#!/bin/bash
set -euo pipefail
# V51
### === UTILS === ###
ask() {
  local prompt="$1"
  local default="${2:-}"
  read -rp "$prompt${default:+ [$default]}: " reply
  echo "${reply:-$default}"
}

ask_yesno() {
  while true; do
    read -rp "$1 [o/n]: " yn
    case "$yn" in
      [Oo]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Répondez par o ou n." ;;
    esac
  done
}

log() {
  echo -e "\e[1;34m==> $1\e[0m"
}

error_exit() {
  echo -e "\e[1;31mErreur: $1\e[0m"
  exit 1
}

### === DÉTECTION DU MODE DE DÉMARRAGE === ###
detect_boot_mode() {
  [[ -d /sys/firmware/efi ]] && echo "UEFI" || echo "Legacy"
}

### === CHOIX DU DISQUE === ###
choose_disk() {
  log "Liste des disques disponibles :"
  lsblk -dpno NAME,SIZE | grep -v "loop"
  while true; do
    disk=$(ask "Entrez le disque cible (ex: /dev/sda)")
    [[ -b "$disk" ]] || { echo "Disque invalide."; continue; }
    read -rp "Confirmer l'effacement de toutes les données sur $disk ? [o/n]: " confirm
    [[ "$confirm" =~ [Oo] ]] && break
  done
  echo "$disk"
}

### === PARTITIONNEMENT AUTOMATIQUE === ###
auto_partition() {
  local disk="$1" boot_mode="$2"
  log "Création d'une table GPT sur $disk..."
  parted -s "$disk" mklabel gpt

  log "Création des partitions..."
  if [[ "$boot_mode" == "UEFI" ]]; then
    parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    boot_part="${disk}1"
  else
    parted -s "$disk" mkpart primary ext4 1MiB 513MiB
    parted -s "$disk" set 1 boot on
    boot_part="${disk}1"
  fi

  parted -s "$disk" mkpart primary linux-swap 513MiB 4GiB
  swap_part="${disk}2"

  parted -s "$disk" mkpart primary ext4 4GiB 100%
  root_part="${disk}3"

  log "Rafraîchissement des partitions..."
  partprobe "$disk"
}

### === FORMATAGE === ###
format_partitions() {
  log "Formatage des partitions..."

  [[ -n "${boot_part:-}" ]] && {
    if [[ "$boot_mode" == "UEFI" ]]; then
      mkfs.fat -F32 "$boot_part"
    else
      mkfs.ext4 "$boot_part"
    fi
  }

  mkfs.ext4 "$root_part"

  [[ -n "${swap_part:-}" ]] && {
    mkswap "$swap_part"
    swapon "$swap_part"
  }
}

### === MONTAGE === ###
mount_partitions() {
  log "Montage de la racine..."
  mount "$root_part" /mnt

  if [[ -n "${boot_part:-}" ]]; then
    mkdir -p /mnt/boot
    mount "$boot_part" /mnt/boot
  fi
}

### === INSTALLATION DE BASE === ###
install_base() {
  log "Installation de base d'Arch Linux..."
  pacstrap /mnt base linux linux-firmware base-devel networkmanager sudo grub
}

### === CONFIGURATION SYSTÈME === ###
configure_system() {
  local hostname="$1" username="$2" userpass="$3" rootpass="$4"

  log "Configuration système..."
  genfstab -U /mnt >> /mnt/etc/fstab

  arch-chroot /mnt bash -e <<EOF
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo 'fr_FR.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "$hostname" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$rootpass" | chpasswd
useradd -m -G wheel "$username"
echo "$username:$userpass" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

systemctl enable NetworkManager
EOF
}

### === INSTALL BOOTLOADER === ###
install_bootloader() {
  log "Installation du bootloader GRUB..."
  if [[ "$boot_mode" == "UEFI" ]]; then
    arch-chroot /mnt pacman -S --noconfirm efibootmgr
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  else
    arch-chroot /mnt grub-install --target=i386-pc "$disk"
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

### === INSTALL ENVIRONNEMENT GRAPHIQUE === ###
install_desktop_env() {
  local env="$1"
  log "Installation de l’environnement $env..."

  case "$env" in
    gnome)
      arch-chroot /mnt pacman -S --noconfirm gnome gnome-extra gdm
      arch-chroot /mnt systemctl enable gdm
      ;;
    kde)
      arch-chroot /mnt pacman -S --noconfirm plasma kde-applications sddm
      arch-chroot /mnt systemctl enable sddm
      ;;
    xfce)
      arch-chroot /mnt pacman -S --noconfirm xfce4 lightdm lightdm-gtk-greeter
      arch-chroot /mnt systemctl enable lightdm
      ;;
    hyprland)
      arch-chroot /mnt pacman -S --noconfirm hyprland xorg-server xorg-xinit kitty waybar
      ;;
    minimal)
      echo "Pas d’environnement graphique installé."
      ;;
  esac
}

### === PAQUETS SUPPLÉMENTAIRES === ###
install_extra() {
  read -rp "Ajouter des paquets supplémentaires ? (ex: firefox nano htop): " extras
  [[ -n "$extras" ]] && arch-chroot /mnt pacman -S --noconfirm $extras
}

### === MAIN === ###
main() {
  clear
  log "Démarrage de l'installation Arch Linux..."

  disk=$(choose_disk)
  boot_mode=$(detect_boot_mode)
  echo "Mode de démarrage : $boot_mode"

  auto_partition "$disk" "$boot_mode"
  format_partitions
  mount_partitions
  install_base

  hostname=$(ask "Nom de la machine" "archlinux")
  username=$(ask "Nom d’utilisateur")
  userpass=$(ask "Mot de passe utilisateur")
  rootpass=$(ask "Mot de passe root")

  configure_system "$hostname" "$username" "$userpass" "$rootpass"
  install_bootloader

  echo "Choisissez un environnement graphique :"
  echo "1) GNOME"
  echo "2) KDE"
  echo "3) XFCE"
  echo "4) Hyprland"
  echo "5) Aucun (installation minimale)"
  while true; do
    env_choice=$(ask "Choix (1-5)")
    case "$env_choice" in
      1) env="gnome"; break ;;
      2) env="kde"; break ;;
      3) env="xfce"; break ;;
      4) env="hyprland"; break ;;
      5) env="minimal"; break ;;
      *) echo "Choix invalide" ;;
    esac
  done

  install_desktop_env "$env"
  install_extra

  log "Installation terminée avec succès !"
  echo "Vous pouvez maintenant démonter et redémarrer."
}

main
