#!/usr/bin/env zsh

# =============================================================================
# ARCH LINUX FR INSTALL 2025 - UEFI/BIOS COMPATIBLE
# =============================================================================
# Version: 2025.1-mod
# Description: Script d'installation automatisée d'Arch Linux optimisé pour la France
# Compatible UEFI et Legacy BIOS
# =============================================================================

set -e  # Arrêt du script en cas d'erreur

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/arch_install.log"
DISK="/dev/sda"
USERNAME="cyber"
HOSTNAME="cyber"
BOOT_MODE=""

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    log "SUCCESS: $1"
}

log_info() {
    log "INFO: $1"
}

log_warning() {
    log "WARNING: $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Fonction de vérification des prérequis
check_prerequisites() {
    log "=== VERIFICATION DES PREREQUIS ==="
    
    # Vérification connexion internet
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_exit "Pas de connexion internet détectée"
    fi
    log_success "Connexion internet OK"
    
    # Détection du mode de boot (UEFI ou BIOS)
    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="uefi"
        log_success "Mode UEFI détecté"
    else
        BOOT_MODE="bios"
        log_success "Mode BIOS Legacy détecté"
    fi
    
    # Vérification existence du disque
    if [[ ! -b "$DISK" ]]; then
        error_exit "Disque $DISK non trouvé"
    fi
    log_success "Disque $DISK détecté"
    
    # Configuration clavier français
    loadkeys fr
    log_success "Clavier français configuré"
}

# Fonction de partitionnement automatique avec détection de taille
auto_partition() {
    local disk=$1
    
    log "=== PARTITIONNEMENT AUTOMATIQUE ($BOOT_MODE) ==="
    
    # Détection de la taille du disque en GB
    local disk_size=$(lsblk -b -d -n -o SIZE "$disk" | head -1)
    local disk_size_gb=$((disk_size / 1024 / 1024 / 1024))
    
    log "Disque: $disk"
    log "Taille détectée: ${disk_size_gb} GB"
    log "Mode de boot: $BOOT_MODE"
    
    # Calcul automatique des tailles selon le disque
    local boot_size="512M"  # Pour BIOS ou EFI
    local swap_size
    local root_size
    local home_size
    local has_separate_home=true
    
    if [[ $disk_size_gb -lt 64 ]]; then
        error_exit "Disque trop petit (minimum 64 GB requis)"
    elif [[ $disk_size_gb -le 128 ]]; then
        # Disque <= 128 GB
        swap_size="2G"
        root_size="30G"
        has_separate_home=false
        log "Configuration petit disque (≤128 GB):"
        if [[ $BOOT_MODE == "uefi" ]]; then
            log "  EFI: $boot_size, SWAP: $swap_size, ROOT: $root_size (avec /home intégré)"
        else
            log "  BOOT: $boot_size, SWAP: $swap_size, ROOT: $root_size (avec /home intégré)"
        fi
        log "  DATA: Reste du disque (~$((disk_size_gb - 33)) GB)"
    elif [[ $disk_size_gb -le 256 ]]; then
        # Disque <= 256 GB
        swap_size="4G"
        root_size="50G"
        home_size="$((disk_size_gb - 80))G"
        log "Configuration disque moyen (≤256 GB):"
        if [[ $BOOT_MODE == "uefi" ]]; then
            log "  EFI: $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        else
            log "  BOOT: $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        fi
        log "  DATA: Reste du disque (~25 GB)"
    elif [[ $disk_size_gb -le 512 ]]; then
        # Disque <= 512 GB
        swap_size="8G"
        root_size="60G"
        home_size="200G"
        log "Configuration disque moyen-grand (≤512 GB):"
        if [[ $BOOT_MODE == "uefi" ]]; then
            log "  EFI: $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        else
            log "  BOOT: $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        fi
        log "  DATA: Reste du disque (~$((disk_size_gb - 269)) GB)"
    else
        # Disque > 512 GB
        swap_size="16G"
        root_size="80G"
        home_size="300G"
        log "Configuration grand disque (>512 GB):"
        if [[ $BOOT_MODE == "uefi" ]]; then
            log "  EFI: $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        else
            log "  BOOT: $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        fi
        log "  DATA: Reste du disque (~$((disk_size_gb - 397)) GB)"
    fi
    
    echo ""
    echo "ATTENTION: Cela va effacer toutes les données du disque $disk!"
    read -p "Voulez-vous continuer avec cette configuration? [y/N]: " confirm
    
    if [[ $confirm != [yY] ]]; then
        log "Partitionnement annulé par l'utilisateur"
        exit 0
    fi
    
    # Partitionnement selon le mode de boot
    if [[ $BOOT_MODE == "uefi" ]]; then
        partition_uefi "$disk" "$boot_size" "$swap_size" "$root_size" "$home_size" "$has_separate_home"
    else
        partition_bios "$disk" "$boot_size" "$swap_size" "$root_size" "$home_size" "$has_separate_home"
    fi
    
    echo "$has_separate_home" > /tmp/has_separate_home
    echo "$BOOT_MODE" > /tmp/boot_mode
}

# Partitionnement UEFI (GPT)
partition_uefi() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6
    
    log "Partitionnement UEFI/GPT..."
    
    # Nettoyage du disque
    sgdisk --zap-all "$disk" || error_exit "Échec du nettoyage du disque"
    
    # Création des partitions avec sgdisk
    if [[ $has_separate_home == false ]]; then
        # Configuration sans partition home séparée
        sgdisk --clear \
               --new=1:0:+$boot_size --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$swap_size --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$root_size --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:0 --typecode=4:8300 --change-name=4:'Linux data' \
               "$disk" || error_exit "Échec de la création des partitions"
    else
        # Configuration complète avec partition home
        sgdisk --clear \
               --new=1:0:+$boot_size --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$swap_size --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$root_size --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:+$home_size --typecode=4:8302 --change-name=4:'Linux home' \
               --new=5:0:0 --typecode=5:8300 --change-name=5:'Linux data' \
               "$disk" || error_exit "Échec de la création des partitions"
    fi
    
    # Attendre que le kernel reconnaisse les nouvelles partitions
    sleep 2
    partprobe "$disk"
    sleep 2
}

# Partitionnement BIOS (MBR)
partition_bios() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6
    
    log "Partitionnement BIOS/MBR..."
    
    # Nettoyage du disque
    dd if=/dev/zero of="$disk" bs=512 count=1 2>/dev/null || true
    
    # Création de la table de partition MBR avec fdisk
    if [[ $has_separate_home == false ]]; then
        # Configuration sans partition home séparée
        fdisk "$disk" << EOF
n
p
1

+$boot_size
a
1
n
p
2

+$swap_size
n
p
3

+$root_size
n
p


t
2
82
w
EOF
    else
        # Configuration avec partition home (utilisation de partitions étendues)
        fdisk "$disk" << EOF
n
p
1

+$boot_size
a
1
n
p
2

+$swap_size
n
p
3

+$root_size
n
e


n

+$home_size
n


t
2
82
w
EOF
    fi
    
    # Attendre que le kernel reconnaisse les nouvelles partitions
    sleep 2
    partprobe "$disk"
    sleep 2
}

# Fonction de partitionnement manuel
manual_partition() {
    local disk=$1
    
    log "=== PARTITIONNEMENT MANUEL ($BOOT_MODE) ==="
    
    if [[ $BOOT_MODE == "uefi" ]]; then
        cat << EOF
Partitionnement manuel UEFI de $disk avec gdisk
Suivez ces étapes dans gdisk:

1. Nettoyage de la table de partition:
   Command: o
   Confirm: Y

2. EFI partition (boot) - 512M:
   Command: n
   Partition number: ENTER (1)
   First sector: ENTER
   Last sector: +512M
   Hex code: EF00

3. SWAP partition - 4G:
   Command: n
   Partition number: ENTER (2)
   First sector: ENTER
   Last sector: +4G
   Hex code: 8200

4. Root partition (/) - 50G:
   Command: n
   Partition number: ENTER (3)
   First sector: ENTER
   Last sector: +50G
   Hex code: 8304

5. Home partition - 100G:
   Command: n
   Partition number: ENTER (4)
   First sector: ENTER
   Last sector: +100G
   Hex code: 8302

6. Data partition - reste du disque:
   Command: n
   Partition number: ENTER (5)
   First sector: ENTER
   Last sector: ENTER
   Hex code: ENTER (8300)

7. Sauvegarde et quitte:
   Command: w
   Confirm: Y

EOF
        read -p "Appuyez sur Entrée pour lancer gdisk..."
        gdisk "$disk"
    else
        cat << EOF
Partitionnement manuel BIOS de $disk avec fdisk
Suivez ces étapes dans fdisk:

1. Créer une nouvelle table de partition DOS:
   Command: o

2. Boot partition - 512M:
   Command: n
   Partition type: p
   Partition number: ENTER (1)
   First sector: ENTER
   Last sector: +512M
   
   Marquer comme bootable:
   Command: a
   Partition number: 1

3. SWAP partition - 4G:
   Command: n
   Partition type: p
   Partition number: ENTER (2)
   First sector: ENTER
   Last sector: +4G
   
   Changer le type:
   Command: t
   Partition number: 2
   Hex code: 82

4. Root partition (/) - 50G:
   Command: n
   Partition type: p
   Partition number: ENTER (3)
   First sector: ENTER
   Last sector: +50G

5. Extended partition - reste du disque:
   Command: n
   Partition type: e
   Partition number: ENTER (4)
   First sector: ENTER
   Last sector: ENTER

6. Home partition logique - 100G:
   Command: n
   First sector: ENTER
   Last sector: +100G

7. Data partition logique - reste:
   Command: n
   First sector: ENTER
   Last sector: ENTER

8. Sauvegarder:
   Command: w

EOF
        read -p "Appuyez sur Entrée pour lancer fdisk..."
        fdisk "$disk"
    fi
    
    echo "true" > /tmp/has_separate_home
    echo "$BOOT_MODE" > /tmp/boot_mode
}

# Menu de choix du partitionnement
partition_menu() {
    log "=== CHOIX DU PARTITIONNEMENT ==="
    
    echo ""
    echo "=============================================================="
    echo "                CHOIX DU PARTITIONNEMENT                     "
    echo "=============================================================="
    echo "Mode de boot détecté: $BOOT_MODE"
    echo ""
    echo "1) Partitionnement automatique (recommandé)"
    echo "2) Partitionnement manuel avec $(if [[ $BOOT_MODE == "uefi" ]]; then echo "gdisk"; else echo "fdisk"; fi)"
    echo "3) Passer (partitions déjà créées)"
    echo ""
    read -p "Votre choix [1-3]: " choice
    
    case $choice in
        1)
            log_info "Partitionnement automatique sélectionné"
            auto_partition "$DISK"
            ;;
        2)
            log_info "Partitionnement manuel sélectionné"
            manual_partition "$DISK"
            ;;
        3)
            log_info "Partitionnement ignoré"
            echo "true" > /tmp/has_separate_home
            echo "$BOOT_MODE" > /tmp/boot_mode
            ;;
        *)
            log_warning "Choix invalide, partitionnement automatique par défaut"
            auto_partition "$DISK"
            ;;
    esac
}

# Formatage des partitions
format_partitions() {
    log "=== FORMATAGE DES PARTITIONS ==="
    
    local has_separate_home="true"
    local boot_mode="uefi"
    
    if [[ -f /tmp/has_separate_home ]]; then
        has_separate_home=$(cat /tmp/has_separate_home)
    fi
    
    if [[ -f /tmp/boot_mode ]]; then
        boot_mode=$(cat /tmp/boot_mode)
    fi
    
    if [[ $boot_mode == "uefi" ]]; then
        log "Formatage de la partition EFI..."
        mkfs.fat -F32 "${DISK}1" || error_exit "Échec formatage EFI"
    else
        log "Formatage de la partition boot..."
        mkfs.ext4 -F "${DISK}1" || error_exit "Échec formatage boot"
    fi
    
    log "Configuration du swap..."
    mkswap "${DISK}2" || error_exit "Échec configuration swap"
    
    log "Formatage de la partition root..."
    mkfs.ext4 -F "${DISK}3" || error_exit "Échec formatage root"
    
    if [[ $has_separate_home == "true" ]]; then
        if [[ $boot_mode == "bios" ]]; then
            # En BIOS avec partitions étendues
            log "Formatage de la partition home..."
            mkfs.ext4 -F "${DISK}5" || error_exit "Échec formatage home"
            
            log "Formatage de la partition data..."
            mkfs.ext4 -F "${DISK}6" || error_exit "Échec formatage data"
        else
            # En UEFI
            log "Formatage de la partition home..."
            mkfs.ext4 -F "${DISK}4" || error_exit "Échec formatage home"
            
            log "Formatage de la partition data..."
            mkfs.ext4 -F "${DISK}5" || error_exit "Échec formatage data"
        fi
    else
        log "Formatage de la partition data..."
        mkfs.ext4 -F "${DISK}4" || error_exit "Échec formatage data"
    fi
    
    log "Formatage terminé"
}

# Montage des partitions
mount_partitions() {
    log "=== MONTAGE DES PARTITIONS ==="
    
    local has_separate_home="true"
    local boot_mode="uefi"
    
    if [[ -f /tmp/has_separate_home ]]; then
        has_separate_home=$(cat /tmp/has_separate_home)
    fi
    
    if [[ -f /tmp/boot_mode ]]; then
        boot_mode=$(cat /tmp/boot_mode)
    fi
    
    # Activation du swap
    log "Activation du swap..."
    swapon "${DISK}2" || error_exit "Échec activation swap"
    
    # Montage de la partition root
    log "Montage de la partition root..."
    mount "${DISK}3" /mnt || error_exit "Échec montage root"
    
    # Création des points de montage
    mkdir -p /mnt/{boot,data}
    
    if [[ $has_separate_home == "true" ]]; then
        mkdir -p /mnt/home
        log "Configuration normale: partition /home séparée"
        
        # Montage des partitions selon le mode de boot
        log "Montage des partitions..."
        mount "${DISK}1" /mnt/boot || error_exit "Échec montage boot"
        
        if [[ $boot_mode == "bios" ]]; then
            # Partitions étendues en BIOS
            mount "${DISK}5" /mnt/home || error_exit "Échec montage home"
            mount "${DISK}6" /mnt/data || error_exit "Échec montage data"
        else
            # Partitions normales en UEFI
            mount "${DISK}4" /mnt/home || error_exit "Échec montage home"
            mount "${DISK}5" /mnt/data || error_exit "Échec montage data"
        fi
    else
        log "Configuration petit disque: /home intégré dans /"
        
        log "Montage des partitions..."
        mount "${DISK}1" /mnt/boot || error_exit "Échec montage boot"
        mount "${DISK}4" /mnt/data || error_exit "Échec montage data"
    fi
    
    log "Montage terminé"
    lsblk
}

# Installation de base
install_base() {
    log "=== INSTALLATION DE BASE ==="
    
    # Synchronisation de l'horloge
    log "Synchronisation de l'horloge..."
    timedatectl set-ntp true
    
    # Mise à jour des miroirs
    log "Mise à jour des miroirs..."
    reflector --country France --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    # Installation des paquets de base
    log "Installation des paquets de base..."
    pacstrap /mnt base base-devel linux linux-firmware vim openssh intel-ucode || error_exit "Échec installation base"
    
    # Génération du fstab
    log "Génération du fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab || error_exit "Échec génération fstab"
    
    log "Installation de base terminée"
}

# Configuration système dans chroot
configure_system() {
    log "=== CONFIGURATION SYSTÈME ==="
    
    local boot_mode="uefi"
    if [[ -f /tmp/boot_mode ]]; then
        boot_mode=$(cat /tmp/boot_mode)
    fi
    
    # Copie du script pour continuer en chroot
    cp "$0" /mnt/root/
    cp "$LOG_FILE" /mnt/root/ 2>/dev/null || true
    echo "$boot_mode" > /mnt/root/boot_mode
    
    # Configuration en chroot
    arch-chroot /mnt /bin/zsh << CHROOT_EOF
    
    # Lecture du mode de boot
    BOOT_MODE=\$(cat /root/boot_mode 2>/dev/null || echo "uefi")
    
    # Configuration locale
    echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    
    echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
    echo "LANGUAGE=fr_FR" >> /etc/locale.conf
    echo "LC_ALL=C" >> /etc/locale.conf
    
    echo "KEYMAP=fr" > /etc/vconsole.conf
    
    # Configuration timezone France
    ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
    hwclock --systohc
    
    # Configuration hostname
    echo "$HOSTNAME" > /etc/hostname
    
    # Configuration /etc/hosts
    cat > /etc/hosts << EOF
127.0.0.1	localhost.localdomain	localhost
::1		localhost.localdomain	localhost
127.0.0.1	$HOSTNAME.localdomain	$HOSTNAME
EOF
    
    # Installation des services réseau
    pacman -S --noconfirm dhcpcd networkmanager network-manager-applet
    systemctl enable sshd
    systemctl enable dhcpcd
    systemctl enable NetworkManager
    
    # Installation et configuration GRUB selon le mode de boot
    pacman -S --noconfirm grub
    
    if [[ \$BOOT_MODE == "uefi" ]]; then
        echo "Configuration GRUB pour UEFI..."
        pacman -S --noconfirm efibootmgr
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        echo "Configuration GRUB pour BIOS..."
        grub-install --target=i386-pc $DISK
    fi
    
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Installation des outils supplémentaires
    pacman -S --noconfirm iw wpa_supplicant dialog git reflector lshw unzip htop
    pacman -S --noconfirm wget pulseaudio alsa-utils alsa-plugins pavucontrol xdg-user-dirs
    
    # Configuration mot de passe root
    echo "Configuration du mot de passe root:"
    passwd
    
CHROOT_EOF
    
    log "Configuration système terminée"
}

# Installation environnement graphique
install_gui() {
    log "=== INSTALLATION ENVIRONNEMENT GRAPHIQUE ==="
    
    arch-chroot /mnt /bin/zsh << 'CHROOT_EOF'
    
    # Installation serveur X
    pacman -S --noconfirm xorg-server xorg-apps xorg-xinit
    
    # Installation i3
    pacman -S --noconfirm i3-gaps i3blocks i3lock numlockx
    
    # Installation gestionnaire de connexion
    pacman -S --noconfirm lightdm lightdm-gtk-greeter
    systemctl enable lightdm
    
    # Installation polices
    pacman -S --noconfirm noto-fonts ttf-ubuntu-font-family ttf-dejavu ttf-freefont
    pacman -S --noconfirm ttf-liberation ttf-droid ttf-roboto terminus-font
    
    # Applications de base
    pacman -S --noconfirm rxvt-unicode ranger rofi dmenu firefox vlc
    
    # Thèmes
    pacman -S --noconfirm lxappearance arc-gtk-theme papirus-icon-theme
    
    # Configuration thème lightdm
    cat > /etc/lightdm/lightdm-gtk-greeter.conf << EOF
[greeter]
theme-name = Arc-Dark
icon-theme-name = Papirus-Dark
background = #2f343f
EOF
    
    # Gestion de l'alimentation et optimisations
    pacman -S --noconfirm tlp tlp-rdw powertop acpi acpi_call
    systemctl enable tlp
    systemctl enable tlp-sleep
    systemctl mask systemd-rfkill.service
    systemctl mask systemd-rfkill.socket
    
    # Bluetooth
    pacman -S --noconfirm bluez bluez-utils blueman
    systemctl enable bluetooth
    
    # Optimisation SSD
    systemctl enable fstrim.timer
    
CHROOT_EOF
    
    log "Installation GUI terminée"
}

# Configuration utilisateur
setup_user() {
    log "=== CONFIGURATION UTILISATEUR ==="
    
    arch-chroot /mnt /bin/zsh << CHROOT_EOF
    
    # Création utilisateur
    useradd -m -g users -G wheel,storage,power,audio $USERNAME
    echo "Configuration du mot de passe pour $USERNAME:"
    passwd $USERNAME
    
    # Configuration sudo
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    
CHROOT_EOF
    
    log "Configuration utilisateur terminée"
}

# Nettoyage final
cleanup() {
    log "=== NETTOYAGE FINAL ==="
    
    # Démontage des partitions
    umount -R /mnt 2>/dev/null || true
    swapoff "${DISK}2" 2>/dev/null || true
    
    # Nettoyage des fichiers temporaires
    rm -f /tmp/has_separate_home /tmp/boot_mode
    
    log "Nettoyage terminé"
}

# Script post-installation (à exécuter après le premier redémarrage)
create_post_install_script() {
    log "=== CREATION DU SCRIPT POST-INSTALLATION ==="
    
    cat > /mnt/home/$USERNAME/post_install.sh << 'POST_EOF'
#!/bin/zsh

echo "=== CONFIGURATION POST-INSTALLATION ==="

# Installation AUR helper
cd ~
mkdir -p Sources
cd Sources

if [[ ! -d yay ]]; then
    echo "Installation de yay (AUR helper)..."
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
fi

# Installation paquets AUR
echo "Installation des paquets audio..."
yay -S --noconfirm pa-applet-git

# Configuration shell zsh
echo "Configuration du shell zsh..."
sudo pacman -S --noconfirm zsh
chsh -s /bin/zsh

# Configuration utilisateur
echo "Configuration des dossiers utilisateur..."
xdg-user-dirs-update

echo ""
echo "=============================================================="
echo "            POST-INSTALLATION TERMINEE                       "
echo "=============================================================="
echo "  Votre système Arch Linux est maintenant prêt !             "
echo "                                                              "
echo "  Applications installées:                                    "
echo "  - Firefox (navigateur)                                     "
echo "  - VLC (lecteur multimédia)                                 "
echo "  - Ranger (gestionnaire de fichiers)                       "
echo "  - htop (moniteur système)                                 "
echo "  - Arc-Dark theme + Papirus icons                          "
echo "                                                              "
echo "  Configuration suggérée:                                    "
echo "  git config --global user.name \"Votre Nom\"                 "
echo "  git config --global user.email \"email@example.com\"        "
echo "                                                              "
echo "  Redémarrez le système pour finaliser: sudo reboot          "
echo "=============================================================="

POST_EOF
    
    chmod +x /mnt/home/$USERNAME/post_install.sh
    arch-chroot /mnt chown $USERNAME:users /home/$USERNAME/post_install.sh
    
    log_success "Script post-installation créé: /home/$USERNAME/post_install.sh"
}

# Fonction principale
main() {
    log "=== DEBUT DE L'INSTALLATION ARCH LINUX (UEFI/BIOS) ==="
    log "Fichier de log: $LOG_FILE"
    
    check_prerequisites
    partition_menu
    format_partitions
    mount_partitions
    install_base
    configure_system
    install_gui
    setup_user
    create_post_install_script
    
    log "=== INSTALLATION TERMINEE ==="
    echo ""
    echo "=============================================================="
    echo "                  INSTALLATION TERMINEE                      "
    echo "=============================================================="
    echo "  Mode de boot: $BOOT_MODE"
    echo "  1. Redémarrez le système: reboot                           "
    echo "  2. Connectez-vous avec l'utilisateur: $USERNAME               "
    echo "  3. Exécutez le script post-installation:                   "
    echo "     ./post_install.sh                                       "
    echo "                                                              "
    echo "  Log sauvegardé dans: /root/arch_install.log             "
     echo "  N'oubliez pas de donner une étoile sur GitHub !         "
    echo "=============================================================="
    echo ""
    
    read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_confirm
    if [[ $reboot_confirm == [yY] ]]; then
        cleanup
        reboot
    else
        cleanup
        log "Redémarrage annulé. N'oubliez pas de redémarrer manuellement."
    fi
}

# Point d'entrée du script
if [[ $ZSH_EVAL_CONTEXT == *:file ]]; then
    main "$@"
fi
