#!/bin/bash
set -euo pipefail
# V50
# === Fonctions utilitaires ===

error_exit() {
  echo "[ERROR] $1"
  exit 1
}

debug() {
  echo "[DEBUG] $1"
}

# Ask question with default
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

# Yes/no via whiptail
ask_yesno() {
  local prompt="$1"
  whiptail --yesno "$prompt" 8 60
  return $?
}

# === Detect boot mode ===
detect_boot_mode() {
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo "UEFI"
  else
    echo "Legacy"
  fi
}

# === List disks with size and model ===
list_disks() {
  lsblk -dpno NAME,SIZE,MODEL | grep -v "rom" | awk '{print $1" "$2" "$3}'
}

# === Choose disk ===
choose_disk() {
  local disks=()
  local options=()
  while IFS= read -r line; do
    disks+=("$line")
  done < <(list_disks)
  local i=1
  for d in "${disks[@]}"; do
    local name size model
    read -r name size model <<< "$d"
    options+=("$name" "$size $model")
    ((i++))
  done
  whiptail --title "Choix du disque" --menu "Sélectionnez le disque d'installation:" 15 70 5 "${options[@]}" 3>&1 1>&2 2>&3
}

# === List partitions for disk ===
list_partitions() {
  local disk="$1"
  lsblk -lnpo NAME,SIZE,TYPE,MOUNTPOINT "$disk" | awk '$3=="part" {print $1" "$2" "$4}'
}

# === Choose partition from disk (for root, boot etc) ===
choose_partition() {
  local disk="$1"
  local purpose="$2" # ex: "racine", "/boot" ...
  local parts=()
  local options=()
  while IFS= read -r line; do
    parts+=("$line")
  done < <(list_partitions "$disk")
  if [[ ${#parts[@]} -eq 0 ]]; then
    error_exit "Aucune partition trouvée sur $disk"
  fi

  local i=1
  for p in "${parts[@]}"; do
    local name size mount
    read -r name size mount <<< "$p"
    local label="$size"
    [[ -n "$mount" ]] && label+=" (montée sur $mount)"
    options+=("$name" "$label")
    ((i++))
  done

  whiptail --title "Choix partition $purpose" --menu "Sélectionnez la partition pour $purpose : (ESC = pas de partition)" 15 70 6 "${options[@]}" 3>&1 1>&2 2>&3 || echo ""
}

# === Check and unmount mounted partitions on disk ===
check_and_unmount() {
  local disk=$1
  local mounted_parts
  mounted_parts=$(lsblk -lnpo NAME,MOUNTPOINT "$disk" | awk '$2!="" {print $1}')

  if [[ -n "$mounted_parts" ]]; then
    debug "Partitions montées sur $disk :"
    debug "$mounted_parts"
    if ask_yesno "Des partitions sont montées sur $disk. Voulez-vous les démonter ?"; then
      for part in $mounted_parts; do
        debug "Démontage de $part ..."
        umount -R "$part" || error_exit "Impossible de démonter $part"
      done
      debug "Partitions démontées."
    else
      error_exit "Démontage nécessaire. Relancez le script après."
    fi
  else
    debug "Aucune partition montée sur $disk"
  fi
}

# === Montage des partitions ===
mount_partitions() {
  local boot_part=$1
  local root_part=$2
  local home_part=$3
  local var_part=$4
  local tmp_part=$5
  local data_part=$6

  debug "Montage de la partition racine $root_part sur /mnt"
  mount "$root_part" /mnt || error_exit "Erreur montage /"

  if [[ -n "$boot_part" ]]; then
    mkdir -p /mnt/boot
    debug "Montage de /boot : $boot_part"
    mount "$boot_part" /mnt/boot || error_exit "Erreur montage /boot"
  fi

  if [[ -n "$home_part" ]]; then
    mkdir -p /mnt/home
    debug "Montage de /home : $home_part"
    mount "$home_part" /mnt/home || error_exit "Erreur montage /home"
  fi

  if [[ -n "$var_part" ]]; then
    mkdir -p /mnt/var
    debug "Montage de /var : $var_part"
    mount "$var_part" /mnt/var || error_exit "Erreur montage /var"
  fi

  if [[ -n "$tmp_part" ]]; then
    mkdir -p /mnt/tmp
    debug "Montage de /tmp : $tmp_part"
    mount "$tmp_part" /mnt/tmp || error_exit "Erreur montage /tmp"
  fi

  if [[ -n "$data_part" ]]; then
    mkdir -p /mnt/data
    debug "Montage de /data : $data_part"
    mount "$data_part" /mnt/data || error_exit "Erreur montage /data"
  fi
}

# === Installation base ===
install_base() {
  debug "Installation base systeme (base, linux, firmware)"
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

  debug "Génération du fstab"
  genfstab -U /mnt >> /mnt/etc/fstab

  debug "Configuration locale, hostname, utilisateurs"
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

  debug "Installation bootloader $boot_mode"
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
  debug "Installation environnement $env..."
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
      arch-chroot /mnt pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
      arch-chroot /mnt systemctl enable lightdm
      ;;
    minimal)
      echo "Pas d'environnement graphique installé."
      ;;
    *)
      echo "Environnement inconnu, installation minimale."
      ;;
  esac
}

# === Installer paquets supplémentaires ===
install_extra_packages() {
  local pkgs
  pkgs=$(whiptail --inputbox "Entrez les paquets supplémentaires à installer (espace séparés), ou laissez vide :" 8 60 3>&1 1>&2 2>&3)
  if [[ -n "$pkgs" ]]; then
    arch-chroot /mnt pacman -S --noconfirm $pkgs
  fi
}

# === Finalisation ===
finalize() {
  debug "Démontage des partitions..."
  umount -R /mnt
  debug "Installation terminée."
}

# === MAIN ===

main() {
  boot_mode=$(detect_boot_mode)
  debug "Mode de boot détecté : $boot_mode"

  disk=$(choose_disk) || error_exit "Choix du disque annulé."
  debug "Disque choisi : $disk"

  check_and_unmount "$disk"

  root_part=$(choose_partition "$disk" "racine") || error_exit "Choix partition racine annulé."
  debug "Partition racine : $root_part"

  # Partitions optionnelles via menus
  boot_part=$(choose_partition "$disk" "/boot")
  debug "Partition /boot : ${boot_part:-(none)}"

  home_part=$(choose_partition "$disk" "/home")
  debug "Partition /home : ${home_part:-(none)}"

  var_part=$(choose_partition "$disk" "/var")
  debug "Partition /var : ${var_part:-(none)}"

  tmp_part=$(choose_partition "$disk" "/tmp")
  debug "Partition /tmp : ${tmp_part:-(none)}"

  data_part=$(choose_partition "$disk" "/data")
  debug "Partition /data : ${data_part:-(none)}"

  mount_partitions "$boot_part" "$root_part" "$home_part" "$var_part" "$tmp_part" "$data_part"

  install_base

  hostname=$(whiptail --inputbox "Nom de la machine (hostname)" 8 40 "archlinux" 3>&1 1>&2 2>&3)
  username=$(whiptail --inputbox "Nom de l'utilisateur" 8 40 3>&1 1>&2 2>&3)
  userpass=$(whiptail --passwordbox "Mot de passe utilisateur" 8 40 3>&1 1>&2 2>&3)
  rootpass=$(whiptail --passwordbox "Mot de passe root" 8 40 3>&1 1>&2 2>&3)

  configure_system "$hostname" "$username" "$userpass" "$rootpass" "$boot_mode" "$disk"

  desktop_env=$(whiptail --menu "Choisissez environnement graphique" 15 50 5 \
    hyprland "Hyprland (Wayland)" \
    gnome "GNOME" \
    kde "KDE Plasma" \
    xfce "XFCE" \
    minimal "Minimal sans GUI" 3>&1 1>&2 2>&3)

  install_desktop_env "$desktop_env"

  install_extra_packages

  finalize

  whiptail --msgbox "Installation terminée avec succès !" 8 40
}

main
