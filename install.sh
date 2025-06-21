#!/bin/bash
set -euo pipefail

# === Fonctions utilitaires ===

ask() {
  local prompt="$1"
  local default="${2:-}"
  if [[ -n "$default" ]]; then
    read -rp "$prompt [$default]: " answer
    answer="${answer:-$default}"
  else
    read -rp "$prompt: " answer
  fi
  echo "$answer"
}

ask_yesno() {
  local prompt="$1"
  while true; do
    read -rp "$prompt [o/n]: " yn
    case "$yn" in
      [Oo]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Veuillez répondre par o (oui) ou n (non)." ;;
    esac
  done
}

error_exit() {
  echo "Erreur : $1"
  exit 1
}

# === Vérification et démontage des partitions montées ===
check_and_unmount() {
  local disk=$1
  local mounted_parts
  mounted_parts=$(lsblk -lnpo NAME,MOUNTPOINT "$disk" | awk '$2!="" {print $1}')

  if [[ -n "$mounted_parts" ]]; then
    echo "Partitions montées sur $disk :"
    echo "$mounted_parts"
    if ask_yesno "Voulez-vous démonter ces partitions ?"; then
      for part in $mounted_parts; do
        echo "Démontage de $part ..."
        umount -R "$part" || error_exit "Impossible de démonter $part"
      done
      echo "Partitions démontées."
    else
      error_exit "Démontage nécessaire. Relancez le script après."
    fi
  fi
}

# === Choix du disque ===
choose_disk() {
  echo "Disques disponibles :"
  lsblk -dpno NAME,SIZE,MODEL | grep -v "rom"
  while true; do
    local disk
    disk=$(ask "1) Entrez le disque d'installation (ex: /dev/sda)")
    [[ -b "$disk" ]] || { echo "Ce n'est pas un disque valide."; continue; }
    check_and_unmount "$disk"
    echo "$disk"
    return
  done
}

# === Détection BIOS/UEFI ===
detect_boot_mode() {
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo "UEFI"
  else
    echo "Legacy"
  fi
}

# === Partitionnement automatique ===
partition_auto() {
  local disk=$1
  local boot_mode=$2
  local part_boot_needed=$3
  local part_home_needed=$4
  local part_var_needed=$5
  local part_tmp_needed=$6
  local part_data_needed=$7
  local use_swap_part=$8

  echo "Partitionnement automatique sur $disk ($boot_mode)..."

  parted --script "$disk" mklabel gpt || error_exit "Impossible de créer la table de partition."

  local start=1MiB
  local part_num=1
  local parts=()

  # /boot ou EFI
  if [[ "$boot_mode" == "UEFI" ]]; then
    parted --script "$disk" mkpart ESP fat32 $start 513MiB
    parted --script "$disk" set $part_num boot on
    parts[boot]="${disk}${part_num}"
  elif [[ "$part_boot_needed" -eq 1 ]]; then
    parted --script "$disk" mkpart primary ext4 $start 513MiB
    parts[boot]="${disk}${part_num}"
  fi
  ((part_num++))

  # Swap partition
  if [[ "$use_swap_part" -eq 1 ]]; then
    parted --script "$disk" mkpart primary linux-swap 513MiB 4617MiB
    parts[swap]="${disk}${part_num}"
    ((part_num++))
  fi

  # Taille restante pour root et autres
  parted --script "$disk" mkpart primary ext4 4617MiB 100%
  parts[root]="${disk}${part_num}"

  # Formatage
  echo "Formatage des partitions..."

  if [[ -n "${parts[boot]:-}" ]]; then
    if [[ "$boot_mode" == "UEFI" ]]; then
      mkfs.fat -F32 "${parts[boot]}"
    else
      mkfs.ext4 "${parts[boot]}"
    fi
  fi

  if [[ "$use_swap_part" -eq 1 ]]; then
    mkswap "${parts[swap]}"
    swapon "${parts[swap]}"
  fi

  mkfs.ext4 "${parts[root]}"

  echo "Partitions créées :"
  for k in "${!parts[@]}"; do
    echo "  $k : ${parts[$k]}"
  done

  echo "${parts[boot]} ${parts[root]} ${parts[swap]:-}"
}

# === Montage partitions ===
mount_partitions() {
  local boot_part=$1
  local root_part=$2
  local home_part=$3
  local var_part=$4
  local tmp_part=$5
  local data_part=$6

  mount "$root_part" /mnt || error_exit "Erreur montage /"

  [[ -n "$boot_part" ]] && {
    mkdir -p /mnt/boot
    mount "$boot_part" /mnt/boot || error_exit "Erreur montage /boot"
  }

  [[ -n "$home_part" ]] && {
    mkdir -p /mnt/home
    mount "$home_part" /mnt/home || error_exit "Erreur montage /home"
  }

  [[ -n "$var_part" ]] && {
    mkdir -p /mnt/var
    mount "$var_part" /mnt/var || error_exit "Erreur montage /var"
  }

  [[ -n "$tmp_part" ]] && {
    mkdir -p /mnt/tmp
    mount "$tmp_part" /mnt/tmp || error_exit "Erreur montage /tmp"
  }

  [[ -n "$data_part" ]] && {
    mkdir -p /mnt/data
    mount "$data_part" /mnt/data || error_exit "Erreur montage /data"
  }
}

# === Installation de base ===
install_base() {
  echo "Installation de base..."
  pacstrap /mnt base linux linux-firmware base-devel || error_exit "pacstrap échoué"
}

# === Configuration système ===
configure_system() {
  local hostname=$1
  local username=$2
  local userpass=$3
  local rootpass=$4
  local boot_mode=$5
  local disk=$6

  genfstab -U /mnt >> /mnt/etc/fstab

  arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo 'fr_FR.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo LANG=fr_FR.UTF-8 > /etc/locale.conf
echo "$hostname" > /etc/hostname
echo '127.0.0.1 localhost' >> /etc/hosts
echo '::1       localhost' >> /etc/hosts
echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts
pacman -S --noconfirm networkmanager sudo

systemctl enable NetworkManager

echo "root:$rootpass" | chpasswd
useradd -m -G wheel "$username"
echo "$username:$userpass" | chpasswd
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
EOF

if [[ "$boot_mode" == "UEFI" ]]; then
  arch-chroot /mnt pacman -S --noconfirm efibootmgr grub
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  arch-chroot /mnt pacman -S --noconfirm grub
  arch-chroot /mnt grub-install --target=i386-pc "$disk"
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}


# === Installation environnement graphique ===
install_desktop_env() {
  local env=$1
  echo "Installation environnement $env..."
  case $env in
    hyprland)
      arch-chroot /mnt pacman -S --noconfirm hyprland xorg-server xorg-xinit kitty waybar network-manager-applet
      ;;
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
    minimal)
      echo "Installation minimale, pas d'environnement graphique."
      ;;
    *)
      echo "Environnement inconnu, rien d'installé."
      ;;
  esac
}

# === Installation paquet(s) supplémentaires ===
install_extra_packages() {
  echo "Installation de paquets supplémentaires..."
  echo "Entrez les paquets à installer séparés par des espaces (laisser vide pour aucun):"
  read -r extras
  if [[ -n "$extras" ]]; then
    arch-chroot /mnt pacman -S --noconfirm $extras
  fi
}

# === Main ===
main() {
  clear
  echo "=== Script d'installation Arch Linux automatisée ==="

  disk=$(choose_disk)
  boot_mode=$(detect_boot_mode)
  echo "Mode boot détecté : $boot_mode"

  echo
  echo "Partitionnement automatique ou manuel ?"
  echo "1) Automatique"
  echo "2) Manuel"
  local part_type
  while true; do
    part_type=$(ask "Choix (1 ou 2)")
    [[ "$part_type" == "1" || "$part_type" == "2" ]] && break
    echo "Choix invalide."
  done

  local part_boot= part_root= part_home= part_var= part_tmp= part_data= part_swap=
  local part_boot_needed=0
  local part_home_needed=0
  local part_var_needed=0
  local part_tmp_needed=0
  local part_data_needed=0
  local use_swap_part=0

  if [[ "$part_type" == "1" ]]; then
    echo "Choix des partitions séparées (o/n):"
    ask_yesno "Partition /boot séparée ?" && part_boot_needed=1
    ask_yesno "Partition /home séparée ?" && part_home_needed=1
    ask_yesno "Partition /var séparée ?" && part_var_needed=1
    ask_yesno "Partition /tmp séparée ?" && part_tmp_needed=1
    ask_yesno "Partition /data séparée ?" && part_data_needed=1

    if ask_yesno "Partition swap dédiée ? (sinon swapfile sera créé)"; then
      use_swap_part=1
    else
      use_swap_part=0
    fi

    read -r part_boot part_root part_swap <<< $(partition_auto "$disk" "$boot_mode" "$part_boot_needed" "$part_home_needed" "$part_var_needed" "$part_tmp_needed" "$part_data_needed" "$use_swap_part")

    # Pour partitions séparées autres que boot/home, demande manuelle (plus complexe) ou laisser en racine ici

  else
    echo "Entrer les partitions manuellement :"
    part_boot=$(ask "Partition /boot (laisser vide si non)")
    while true; do
      part_root=$(ask "Partition racine / (obligatoire)")
      [[ -b "$part_root" ]] && break
      echo "Partition racine invalide."
    done
    part_home=$(ask "Partition /home (laisser vide si non)")
    part_var=$(ask "Partition /var (laisser vide si non)")
    part_tmp=$(ask "Partition /tmp (laisser vide si non)")
    part_data=$(ask "Partition /data (laisser vide si non)")
    part_swap=$(ask "Partition swap (laisser vide si pas de swap)")
  fi

  echo
  echo "Choix de l'environnement de bureau :"
  echo "1) Hyprland"
  echo "2) GNOME"
  echo "3) KDE"
  echo "4) XFCE"
  echo "5) Minimal"
  local env_choice
  local env=""
  while true; do
    env_choice=$(ask "Votre choix (1-5)")
    case $env_choice in
      1) env="hyprland"; break ;;
      2) env="gnome"; break ;;
      3) env="kde"; break ;;
      4) env="xfce"; break ;;
      5) env="minimal"; break ;;
      *) echo "Choix invalide." ;;
    esac
  done

  echo
  echo "Installation sur :"
  echo "1) Machine physique"
  echo "2) Machine virtuelle - VirtualBox"
  echo "3) Machine virtuelle - VMware"
  local platform_choice
  local platform=""
  while true; do
    platform_choice=$(ask "Votre choix (1-3)")
    case $platform_choice in
      1) platform="physical"; break ;;
      2) platform="virtualbox"; break ;;
      3) platform="vmware"; break ;;
      *) echo "Choix invalide." ;;
    esac
  done

  echo
  local username=$(ask "Nom utilisateur")
  local userpass userpass_confirm
  while true; do
    userpass=$(ask "Mot de passe utilisateur")
    userpass_confirm=$(ask "Confirmez mot de passe")
    [[ "$userpass" == "$userpass_confirm" ]] && break || echo "Mots de passe différents."
  done

  local rootpass rootpass_confirm
  while true; do
    rootpass=$(ask "Mot de passe root")
    rootpass_confirm=$(ask "Confirmez mot de passe root")
    [[ "$rootpass" == "$rootpass_confirm" ]] && break || echo "Mots de passe différents."
  done

  # Montage partitions
  mount_partitions "$part_boot" "$part_root" "$part_home" "$part_var" "$part_tmp" "$part_data"

  # Installation de base
  install_base

  # Configuration système
  configure_system "archlinux" "$username" "$userpass" "$rootpass" "$boot_mode"

  # Installation environnement graphique
  install_desktop_env "$env"

  # Paquets supplémentaires
  install_extra_packages

  echo "Installation terminée. Pensez à démonter et redémarrer."
}

main "$@"
