#!/bin/bash
set -euo pipefail
# V.48
# === Debug ===
debug() {
  echo "[DEBUG] $1"
}

error_exit() {
  echo "[ERREUR] $1" >&2
  exit 1
}

# === Fonctions interactives ===
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

# === Choix du disque ===
choose_disk() {
  local disks parts disk choice

  debug "Liste des disques disponibles"
  mapfile -t disks < <(lsblk -dno NAME,SIZE,MODEL | grep -v "rom")

  if [[ ${#disks[@]} -eq 0 ]]; then
    error_exit "Aucun disque trouvé"
  fi

  local options=()
  for line in "${disks[@]}"; do
    local name size model
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    model=$(echo "$line" | cut -d ' ' -f3-)
    options+=("/dev/$name" "$size - $model")
  done

  debug "Ouverture menu choix disque"
  choice=$(whiptail --title "Choix du disque" --menu "Sélectionnez le disque cible:" 15 60 6 "${options[@]}" 3>&1 1>&2 2>&3) || error_exit "Abandon du choix disque"

  echo "$choice"
}

# === Choix partition racine ===
choose_partition() {
  local disk=$1 parts choice

  debug "Liste des partitions pour $disk"
  mapfile -t parts < <(lsblk -no NAME,SIZE,TYPE,MOUNTPOINT "$disk" | grep part)

  if [[ ${#parts[@]} -eq 0 ]]; then
    error_exit "Aucune partition sur $disk"
  fi

  local options=()
  for line in "${parts[@]}"; do
    local name size mp
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    mp=$(echo "$line" | awk '{print $4}')
    [[ -z "$mp" ]] && mp="non monté"
    options+=("/dev/$name" "$size - $mp")
  done

  debug "Ouverture menu choix partition racine"
  choice=$(whiptail --title "Choix partition racine" --menu "Sélectionnez la partition racine:" 15 70 8 "${options[@]}" 3>&1 1>&2 2>&3) || error_exit "Abandon du choix partition"

  echo "$choice"
}

# === Détection boot mode ===
detect_boot_mode() {
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo "UEFI"
  else
    echo "Legacy"
  fi
}

# === Vérifier et démonter partitions montées ===
check_and_unmount() {
  local disk=$1
  debug "Vérification des partitions montées sur $disk"
  local mounted_parts
  mounted_parts=$(lsblk -lnpo NAME,MOUNTPOINT "$disk" | awk '$2!="" {print $1}')
  if [[ -n "$mounted_parts" ]]; then
    echo "Partitions montées sur $disk:"
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
  else
    debug "Aucune partition montée sur $disk"
  fi
}

# === Montage partitions ===
mount_partitions() {
  local boot_part=$1
  local root_part=$2
  local home_part=$3
  local var_part=$4
  local tmp_part=$5
  local data_part=$6

  debug "Montage de la partition racine $root_part"
  mount "$root_part" /mnt || error_exit "Erreur montage /"

  if [[ -n "$boot_part" ]]; then
    mkdir -p /mnt/boot
    debug "Montage de /boot $boot_part"
    mount "$boot_part" /mnt/boot || error_exit "Erreur montage /boot"
  fi

  if [[ -n "$home_part" ]]; then
    mkdir -p /mnt/home
    debug "Montage de /home $home_part"
    mount "$home_part" /mnt/home || error_exit "Erreur montage /home"
  fi

  if [[ -n "$var_part" ]]; then
    mkdir -p /mnt/var
    debug "Montage de /var $var_part"
    mount "$var_part" /mnt/var || error_exit "Erreur montage /var"
  fi

  if [[ -n "$tmp_part" ]]; then
    mkdir -p /mnt/tmp
    debug "Montage de /tmp $tmp_part"
    mount "$tmp_part" /mnt/tmp || error_exit "Erreur montage /tmp"
  fi

  if [[ -n "$data_part" ]]; then
    mkdir -p /mnt/data
    debug "Montage de /data $data_part"
    mount "$data_part" /mnt/data || error_exit "Erreur montage /data"
  fi
}

# === Installation de base ===
install_base() {
  echo "Installation de base (base, linux, firmware)..."
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

  echo "Génération du fstab..."
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

  echo "Installation du bootloader..."

  if [[ "$boot_mode" == "UEFI" ]]; then
    arch-chroot /mnt pacman -S --noconfirm efibootmgr grub
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB || error_exit "Erreur grub-install UEFI"
  else
    arch-chroot /mnt pacman -S --noconfirm grub
    arch-chroot /mnt grub-install --target=i386-pc "$disk" || error_exit "Erreur grub-install Legacy"
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Erreur grub-mkconfig"
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

# === Installation paquets supplémentaires ===
install_extra_packages() {
  echo "Installation de paquets supplémentaires..."
  echo "Entrez les paquets à installer séparés par des espaces (laisser vide pour aucun):"
  read -r extras
  if [[ -n
