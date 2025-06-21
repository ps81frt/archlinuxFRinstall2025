#!/bin/bash
set -euo pipefail
# V1.2
error_exit() {
  echo "Erreur: $1" >&2
  exit 1
}

debug() {
  echo "[DEBUG] $1"
}

detect_boot_mode() {
  [[ -d /sys/firmware/efi/efivars ]] && echo "UEFI" || echo "BIOS"
}

choose_disk() {
  local opts=()
  while IFS= read -r line; do
    local dev size
    read -r dev size <<< "$line"
    opts+=("$dev" "$size")
  done < <(lsblk -dpno NAME,SIZE | grep -v loop)

  whiptail --title "Choix du disque" \
    --menu "Sélectionnez le disque :" 15 60 ${#opts[@]} \
    "${opts[@]}" 3>&1 1>&2 2>&3 ||
    error_exit "Choix disque annulé."
}

list_partitions() {
  local disk="$1"
  lsblk -lnpo NAME,SIZE,TYPE,MOUNTPOINT "$disk" | awk '$3=="part" {mnt=$4; if(mnt=="") mnt="(non monté)"; print $1" "$2" "mnt}'
}

choose_partition() {
  local disk="$1"
  local purpose="$2"
  local opts=()
  while IFS= read -r line; do
    local dev size mnt
    read -r dev size mnt <<< "$line"
    opts+=("$dev" "$size $mnt")
  done < <(list_partitions "$disk")

  opts+=("" "Ne pas en ajouter")

  whiptail --title "Partition $purpose" \
    --menu "Sélectionnez la partition pour $purpose :" 15 70 ${#opts[@]} \
    "${opts[@]}" 3>&1 1>&2 2>&3 || echo ""
}

confirm_partition_table() {
  local disk="$1"
  local mode="$2"
  whiptail --title "Initialiser" \
    --yesno "Voulez-vous effacer $disk et créer une table $mode ?" 8 60 || exit 1
}


partition_disk() {
  local disk="$1"
  local mode="$2"

  echo "Démontage des partitions sur $disk..."
  for p in $(lsblk -lnpo NAME "$disk"); do
    umount -R "$p" 2>/dev/null || true
  done

  echo "Nettoyage de $disk"
  wipefs -a "$disk" || error_exit "wipefs a échoué."

  echo "Création de la table $mode sur $disk"
  if [ "$mode" = "UEFI" ]; then
    parted -s "$disk" mklabel gpt
  else
    parted -s "$disk" mklabel msdos
  fi
}


format_and_mount() {
  local boot="$1" root="$2" swap="$3"
  mount "$root" /mnt || error_exit "Impossible de monter root ($root)"
  mkdir -p /mnt/boot
  [ -n "$boot" ] && mount "$boot" /mnt/boot
  swapon "$swap" 2>/dev/null || true
  genfstab -U /mnt >> /mnt/etc/fstab
}

install_system() {
  pacstrap /mnt base linux linux-firmware base-devel
  arch-chroot /mnt pacman -S --noconfirm networkmanager sudo grub
}

configure_system() {
  local host="$1" user="$2" pass="$3" rootp="$4" mode="$5" disk="$6"
  arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo LANG=fr_FR.UTF-8 > /etc/locale.conf
echo "$host" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 $host.localdomain $host" >> /etc/hosts
echo "root:$rootp" | chpasswd
useradd -m -G wheel "$user"
echo "$user:$pass" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
systemctl enable NetworkManager
EOF

  if [ "$mode" = "UEFI" ]; then
    arch-chroot /mnt pacman -S --noconfirm efibootmgr
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  else
    arch-chroot /mnt grub-install --target=i386-pc "$disk"
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

choose_desktop() {
  whiptail --title "Environnement" \
    --menu "Choisissez un environnement :" 15 60 5 \
    hyprland "Hyprland" \
    gnome "GNOME" \
    kde "KDE Plasma" \
    xfce "XFCE" \
    minimal "Aucun" 3>&1 1>&2 2>&3 || echo "minimal"
}

install_desktop() {
  case "$1" in
    hyprland) arch-chroot /mnt pacman -S --noconfirm hyprland xorg xinit ;;
    gnome) arch-chroot /mnt pacman -S --noconfirm gnome gnome-extra gdm && arch-chroot /mnt systemctl enable gdm ;;
    kde) arch-chroot /mnt pacman -S --noconfirm plasma kde-applications sddm && arch-chroot /mnt systemctl enable sddm ;;
    xfce) arch-chroot /mnt pacman -S --noconfirm xfce4 lightdm lightdm-gtk-greeter && arch-chroot /mnt systemctl enable lightdm ;;
  esac
}

final_message() {
  umount -R /mnt
  swapoff -a || true
  whiptail --msgbox "Installation terminée !" 8 40
}

main() {
  mode=$(detect_boot_mode)
  debug "Mode : $mode"

  disk=$(choose_disk)
  debug "Disque : $disk"

  confirm_partition_table "$disk" "$mode"
  partition_disk "$disk" "$mode"

  root=$(choose_partition "$disk" "racine")
  boot=""
  [ "$mode" = "UEFI" ] && boot=$(choose_partition "$disk" "EFI (/boot)") || boot=""
  swap=$(choose_partition "$disk" "swap")
  [ -z "$swap" ] && {
    whiptail --yesno "Créer un fichier swap ?" 8 60 && {
      arch-chroot /mnt fallocate -l 2G /swapfile
      arch-chroot /mnt chmod 600 /swapfile
      arch-chroot /mnt mkswap /swapfile
      swap="/swapfile"
    }
  }

  format_and_mount "$boot" "$root" "$swap"
  install_system

  host=$(whiptail --inputbox "Hostname" 8 40 "$HOSTNAME" 3>&1 1>&2 2>&3)
  user=$(whiptail --inputbox "Utilisateur" 8 40 3>&1 1>&2 2>&3)
  pass=$(whiptail --passwordbox "Mot de passe utilisateur" 8 40 3>&1 1>&2 2>&3)
  rootp=$(whiptail --passwordbox "Mot de passe root" 8 40 3>&1 1>&2 2>&3)

  configure_system "$host" "$user" "$pass" "$rootp" "$mode" "$disk"

  desktop=$(choose_desktop)
  install_desktop "$desktop"

  install_extra=$(whiptail --inputbox "Paquets supplémentaires (espace séparés)" 8 60 3>&1 1>&2 2>&3)
  [ -n "$install_extra" ] && arch-chroot /mnt pacman -S --noconfirm $install_extra

  final_message
}

main
