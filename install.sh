#!/bin/bash
set -euo pipefail
shopt -s nullglob

# --- Fonctions utilitaires ---

log() {
    echo -e "\e[1;34m[INFO]\e[0m $*"
}

error() {
    echo -e "\e[1;31m[ERREUR]\e[0m $*" >&2
    exit 1
}

ask() {
    local prompt="$1"
    local default="${2:-}"
    local response
    if [ -n "$default" ]; then
        read -rp "$prompt [$default]: " response
        response="${response:-$default}"
    else
        read -rp "$prompt: " response
    fi
    echo "$response"
}

ask_password() {
    local pass1 pass2
    while true; do
        read -rsp "Mot de passe : " pass1
        echo
        read -rsp "Confirmez le mot de passe : " pass2
        echo
        [[ "$pass1" == "$pass2" ]] && { echo "$pass1"; return 0; }
        echo "Les mots de passe ne correspondent pas, veuillez réessayer."
    done
}

is_mounted() {
    mountpoint -q "$1"
}

mount_partition() {
    local part=$1
    local mount_point=$2

    if ! [ -b "$part" ]; then
        error "Partition $part n'existe pas."
    fi

    if is_mounted "$mount_point"; then
        log "Le point de montage $mount_point est déjà monté, démontage..."
        umount -R "$mount_point" || error "Impossible de démonter $mount_point"
    fi

    mkdir -p "$mount_point"
    mount "$part" "$mount_point" || error "Montage de $part sur $mount_point échoué."
    log "Monté $part sur $mount_point"
}

activate_swap() {
    local swap_part=$1
    if ! [ -b "$swap_part" ]; then
        error "Partition swap $swap_part invalide."
    fi
    swapon "$swap_part" || error "Activation swap $swap_part échouée."
    log "Swap activé sur $swap_part"
}

detect_boot_mode() {
    if [ -d /sys/firmware/efi/efivars ]; then
        echo "uefi"
    else
        echo "legacy"
    fi
}

install_packages() {
    local pkgs=("$@")
    if ! pacman -Sy --noconfirm "${pkgs[@]}"; then
        error "Installation des paquets ${pkgs[*]} échouée."
    fi
}

# --- Début du script principal ---

log "=== Installation interactive Arch Linux ==="

# Choix installation VM ou Hard
install_type=$(ask "Type d'installation (1) Matériel réel, (2) Machine virtuelle" "1")

vm_pkgs=()
if [[ "$install_type" == "2" ]]; then
    vm_choice=$(ask "Choix hyperviseur VM : (1) VirtualBox, (2) QEMU/KVM, (3) VMware" "1")
    case "$vm_choice" in
        1) vm_pkgs=(virtualbox-guest-utils) ;;
        2) vm_pkgs=(qemu-guest-agent) ;;
        3) vm_pkgs=(open-vm-tools) ;;
        *) log "Choix hyperviseur invalide, aucun paquet VM installé." ;;
    esac
fi

boot_mode=$(detect_boot_mode)
log "Mode de démarrage détecté : $boot_mode"

# Montage partitions
mount_choice=$(ask "Montage (1) automatique, (2) manuel" "1")

if [[ "$mount_choice" == "1" ]]; then
    if [[ "$boot_mode" == "uefi" ]]; then
        part_efi=$(ask "Partition EFI (ex: /dev/sda1)")
    else
        part_boot=$(ask "Partition /boot séparée (laisser vide si non)")
    fi
    part_root=$(ask "Partition racine / (ex: /dev/sda2)")
    part_swap=$(ask "Partition swap (laisser vide si pas de swap)")

    # Montage automatique
    if is_mounted /mnt; then
        log "/mnt est déjà monté, démontage..."
        umount -R /mnt || error "Échec démontage /mnt"
    fi
    mount_partition "$part_root" /mnt

    if [[ "$boot_mode" == "uefi" ]]; then
        [ -z "$part_efi" ] && error "Partition EFI requise en mode UEFI."
        mount_partition "$part_efi" /mnt/boot/efi
    else
        if [ -n "$part_boot" ]; then
            mount_partition "$part_boot" /mnt/boot
        fi
    fi

    if [ -n "$part_swap" ]; then
        activate_swap "$part_swap"
    fi

elif [[ "$mount_choice" == "2" ]]; then
    log "Montage manuel :"

    echo "Partitions disponibles :"
    lsblk -p -o NAME,SIZE,TYPE,MOUNTPOINT

    while true; do
        line=$(ask "Entrez partition et point de montage (ex: /dev/sda1 /boot), ou 'fin' pour terminer")
        [[ "$line" == "fin" ]] && break
        part=$(echo "$line" | awk '{print $1}')
        mp=$(echo "$line" | awk '{print $2}')
        if [[ -z "$part" || -z "$mp" ]]; then
            log "Entrée invalide, réessayez."
            continue
        fi
        mount_partition "$part" "/mnt/${mp#/}"
    done

    want_swap=$(ask "Activer une partition swap ? (oui/non)" "non")
    if [[ "$want_swap" =~ ^(oui|o|yes|y)$ ]]; then
        part_swap=$(ask "Partition swap")
        activate_swap "$part_swap"
    fi
else
    error "Choix montage invalide."
fi

# Installation de base
log "Installation de base : base, linux, linux-firmware..."
install_packages base linux linux-firmware

if [[ "$boot_mode" == "uefi" ]]; then
    install_packages efibootmgr
else
    install_packages grub
fi

log "Génération du fichier fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration chroot
log "Entrée dans le chroot pour configuration..."

arch-chroot /mnt /bin/bash -c '

set -euo pipefail

echo "Configuration locale et hostname..."

ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

echo "LANG=fr_FR.UTF-8" > /etc/locale.conf

hostname="$(read -rp "Nom de la machine (hostname) : " hn && echo "$hn")"
echo "$hostname" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF
'

# Bootloader dans chroot
if [[ "$boot_mode" == "uefi" ]]; then
    log "Installation du bootloader systemd-boot..."
    arch-chroot /mnt /bin/bash -c '
        bootctl install
        cat > /boot/loader/loader.conf <<EOF
default arch
timeout 3
editor 0
EOF

        root_dev=$(findmnt / -o SOURCE -n)
        cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=$root_dev rw
EOF
    '
else
    log "Installation du bootloader GRUB..."
    arch-chroot /mnt /bin/bash -c '
        grub-install --target=i386-pc /dev/sda
        grub-mkconfig -o /boot/grub/grub.cfg
    '
fi

# Création utilisateur et configuration sudo dans chroot
arch-chroot /mnt /bin/bash -c '

set -euo pipefail

username="$(read -rp "Nom d utilisateur à créer : " user && echo "$user")"

while true; do
    read -rsp "Mot de passe pour $username : " pass1
    echo
    read -rsp "Confirmez le mot de passe : " pass2
    echo
    [[ "$pass1" == "$pass2" ]] && break
    echo "Les mots de passe ne correspondent pas, réessayez."
done

useradd -m -G wheel -s /bin/bash "$username"
echo "$username:$pass1" | chpasswd

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
'

# Installation environnement graphique + paquets VM dans chroot
log "Choix environnement graphique..."

wm_choice=$(ask "1) sway, 2) hyprland, 3) bspwm" "1")

case "$wm_choice" in
    1) wm="sway" ;;
    2) wm="hyprland" ;;
    3) wm="bspwm" ;;
    *) wm="sway" ;;
esac

arch-chroot /mnt /bin/bash -c "pacman -Sy --noconfirm $wm"

if [[ "${install_type:-1}" == "2" && ${#vm_pkgs[@]} -gt 0 ]]; then
    log "Installation des paquets VM : ${vm_pkgs[*]}"
    arch-chroot /mnt /bin/bash -c "pacman -Sy --noconfirm ${vm_pkgs[*]}"
fi

log "Installation terminée. Vous pouvez démonter /mnt et redémarrer."
