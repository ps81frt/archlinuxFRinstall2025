#!/usr/bin/bash

# =============================================================================
# ARCH LINUX FR INSTALL 2025 - UEFI/BIOS COMPATIBLE (CORRECTED)
# =============================================================================
# Version: 2025.1-corrected
# Auteur : itdevops
# Libre de droit
# Description: Script d'installation automatisée d'Arch Linux optimisé pour la France
# Compatible UEFI et Legacy BIOS - Corrections apportées
# =============================================================================

set -e  # Arrêt du script en cas d'erreur

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/arch_install.log"
DISK="/dev/sda"
USERNAME="cyber"
HOSTNAME="cyber"
BOOT_MODE=""

# Fonctions de logging
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

# Détection du mode de boot
detect_boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
    log "Boot mode detected: $BOOT_MODE"
}

# Fonction de vérification des prérequis
check_prerequisites() {
    log "=== VERIFICATION DES PREREQUIS ==="
    
    # Vérification connexion internet
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_exit "Pas de connexion internet détectée"
    fi
    log_success "Connexion internet OK"
    
    # Détection du mode de boot
    detect_boot_mode
    log_success "Mode $BOOT_MODE détecté"
    
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
    local boot_size="512M"
    local swap_size
    local root_size
    local home_size
    local has_separate_home=true
    
    if [[ $disk_size_gb -lt 64 ]]; then
        error_exit "Disque trop petit (minimum 64 GB requis)"
    elif [[ $disk_size_gb -le 128 ]]; then
        swap_size="2G"
        root_size="30G"
        has_separate_home=false
        log "Configuration petit disque (≤128 GB):"
        log "  $(if [[ $BOOT_MODE == "uefi" ]]; then echo "EFI"; else echo "BOOT"; fi): $boot_size, SWAP: $swap_size, ROOT: $root_size (avec /home intégré)"
        log "  DATA: Reste du disque (~$((disk_size_gb - 33)) GB)"
    elif [[ $disk_size_gb -le 256 ]]; then
        swap_size="4G"
        root_size="50G"
        home_size="$((disk_size_gb - 80))G"
        log "Configuration disque moyen (≤256 GB):"
        log "  $(if [[ $BOOT_MODE == "uefi" ]]; then echo "EFI"; else echo "BOOT"; fi): $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        log "  DATA: Reste du disque (~25 GB)"
    elif [[ $disk_size_gb -le 512 ]]; then
        swap_size="8G"
        root_size="60G"
        home_size="200G"
        log "Configuration disque moyen-grand (≤512 GB):"
        log "  $(if [[ $BOOT_MODE == "uefi" ]]; then echo "EFI"; else echo "BOOT"; fi): $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
        log "  DATA: Reste du disque (~$((disk_size_gb - 269)) GB)"
    else
        swap_size="16G"
        root_size="80G"
        home_size="300G"
        log "Configuration grand disque (>512 GB):"
        log "  $(if [[ $BOOT_MODE == "uefi" ]]; then echo "EFI"; else echo "BOOT"; fi): $boot_size, SWAP: $swap_size, ROOT: $root_size, HOME: $home_size"
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

# Partitionnement UEFI (GPT) - CORRIGÉ
partition_uefi() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6
    
    log "Partitionnement UEFI/GPT..."
    
    # Nettoyage du disque
    sgdisk --zap-all "$disk" || error_exit "Échec du nettoyage du disque"
    
    # Attendre que les changements soient pris en compte
    sleep 2
    
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
    sleep 3
    partprobe "$disk"
    sleep 2
}

# Partitionnement BIOS (MBR) - CORRIGÉ
partition_bios() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6
    
    log "Partitionnement BIOS/MBR..."
    
    # Nettoyage du disque
    wipefs -af "$disk" || true
    dd if=/dev/zero of="$disk" bs=512 count=1 2>/dev/null || true
    
    # Attendre
    sleep 2
    
    # Création de la table de partition MBR avec fdisk - CORRIGÉ
    if [[ $has_separate_home == false ]]; then
        # Configuration sans partition home séparée (4 partitions primaires)
        {
            echo o      # Nouvelle table de partition DOS
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 1      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo +$boot_size  # Dernier secteur
            echo a      # Activer le flag bootable
            echo 1      # Sur la partition 1
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 2      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo +$swap_size  # Dernier secteur
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 3      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo +$root_size  # Dernier secteur
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 4      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo        # Dernier secteur (reste du disque)
            echo t      # Changer type de partition
            echo 2      # Partition 2
            echo 82     # Type Linux swap
            echo w      # Écrire les changements
        } | fdisk "$disk" || error_exit "Échec du partitionnement BIOS"
    else
        # Configuration avec partition home (utilisation de partitions étendues)
        {
            echo o      # Nouvelle table de partition DOS
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 1      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo +$boot_size  # Dernier secteur
            echo a      # Activer le flag bootable
            echo 1      # Sur la partition 1
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 2      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo +$swap_size  # Dernier secteur
            echo n      # Nouvelle partition
            echo p      # Primaire
            echo 3      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo +$root_size  # Dernier secteur
            echo n      # Nouvelle partition
            echo e      # Étendue
            echo 4      # Numéro de partition
            echo        # Premier secteur (défaut)
            echo        # Dernier secteur (reste du disque)
            echo n      # Nouvelle partition logique
            echo        # Premier secteur (défaut)
            echo +$home_size  # Dernier secteur
            echo n      # Nouvelle partition logique
            echo        # Premier secteur (défaut)
            echo        # Dernier secteur (reste de l'étendue)
            echo t      # Changer type de partition
            echo 2      # Partition 2
            echo 82     # Type Linux swap
            echo w      # Écrire les changements
        } | fdisk "$disk" || error_exit "Échec du partitionnement BIOS"
    fi
    
    # Attendre que le kernel reconnaisse les nouvelles partitions
    sleep 3
    partprobe "$disk"
    sleep 2
}

# Fonction de partitionnement manuel - CORRIGÉE
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

# Préparations des partitions - CORRIGÉE
prepare_disk_for_format() {
    log "Préparation du disque pour formatage..."

    # Désactiver swap sur toutes les partitions du disque
    for swapdev in $(swapon --show=NAME --noheadings 2>/dev/null | grep "^${DISK}" || true); do
        log "Désactivation du swap sur $swapdev"
        swapoff "$swapdev" 2>/dev/null || true
    done

    # Démonter toutes les partitions montées du disque
    for mountpoint in $(lsblk -ln -o NAME,MOUNTPOINT | grep "^$(basename $DISK)" | awk '$2!="" {print $2}' | tac); do
        if [[ -n "$mountpoint" ]]; then
            log "Démontage de $mountpoint"
            umount "$mountpoint" 2>/dev/null || true
        fi
    done

    log "Disque prêt pour formatage"
}

# Formatage des partitions - CORRIGÉ
format_partitions() {
    log "=== FORMATAGE DES PARTITIONS ==="

    local has_separate_home="true"
    local boot_mode="$BOOT_MODE"

    # Lecture config temporaire si disponible
    [[ -f /tmp/has_separate_home ]] && has_separate_home=$(cat /tmp/has_separate_home)
    [[ -f /tmp/boot_mode ]] && boot_mode=$(cat /tmp/boot_mode)

    log "Mode de boot : $boot_mode"
    log "Partition /home séparée : $has_separate_home"

    # Attendre que les partitions soient reconnues
    sleep 2

    # Formatage partition de démarrage selon mode
    if [[ $boot_mode == "uefi" ]]; then
        log "Formatage de la partition EFI ${DISK}1..."
        mkfs.fat -F32 "${DISK}1" || error_exit "Échec formatage EFI"
    else
        log "Formatage de la partition /boot ${DISK}1..."
        mkfs.ext4 -F "${DISK}1" || error_exit "Échec formatage /boot"
    fi

    # Swap commun
    log "Configuration du swap ${DISK}2..."
    mkswap "${DISK}2" || error_exit "Échec configuration swap"

    # Root commun
    log "Formatage de la partition root ${DISK}3..."
    mkfs.ext4 -F "${DISK}3" || error_exit "Échec formatage root"

    # Home et data selon mode et séparé ou non
    if [[ $has_separate_home == "true" ]]; then
        if [[ $boot_mode == "bios" ]]; then
            # En BIOS avec home séparé: partitions logiques 5 et 6
            log "Formatage home ${DISK}5..."
            mkfs.ext4 -F "${DISK}5" || error_exit "Échec formatage home"

            log "Formatage data ${DISK}6..."
            mkfs.ext4 -F "${DISK}6" || error_exit "Échec formatage data"
        else
            # En UEFI avec home séparé: partitions 4 et 5
            log "Formatage home ${DISK}4..."
            mkfs.ext4 -F "${DISK}4" || error_exit "Échec formatage home"

            log "Formatage data ${DISK}5..."
            mkfs.ext4 -F "${DISK}5" || error_exit "Échec formatage data"
        fi
    else
        # Sans home séparée
        if [[ $boot_mode == "bios" ]]; then
            log "Formatage data ${DISK}4 (pas de home séparé)..."
            mkfs.ext4 -F "${DISK}4" || error_exit "Échec formatage data"
        else
            log "Formatage data ${DISK}4 (pas de home séparé)..."
            mkfs.ext4 -F "${DISK}4" || error_exit "Échec formatage data"
        fi
    fi

    log "Formatage terminé"
}

# Montage des partitions - CORRIGÉ
mount_partitions() {
    log "=== MONTAGE DES PARTITIONS ==="

    local has_separate_home="true"
    local boot_mode="$BOOT_MODE"

    [[ -f /tmp/has_separate_home ]] && has_separate_home=$(cat /tmp/has_separate_home)
    [[ -f /tmp/boot_mode ]] && boot_mode=$(cat /tmp/boot_mode)

    log "Mode de boot : $boot_mode"
    log "Partition /home séparée : $has_separate_home"

    # Montage root en premier
    log "Montage root ${DISK}3 sur /mnt..."
    mount "${DISK}3" /mnt || error_exit "Échec montage root"

    # Activation swap
    log "Activation swap ${DISK}2..."
    swapon "${DISK}2" || error_exit "Échec activation swap"

    # Création des points de montage
    mkdir -p /mnt/{boot,data}

    # Montage boot
    log "Montage boot ${DISK}1 sur /mnt/boot..."
    mount "${DISK}1" /mnt/boot || error_exit "Échec montage boot"

    # Montage home et data selon configuration
    if [[ $has_separate_home == "true" ]]; then
        mkdir -p /mnt/home

        if [[ $boot_mode == "bios" ]]; then
            # BIOS avec home séparé: partitions logiques
            log "Montage home ${DISK}5 sur /mnt/home..."
            mount "${DISK}5" /mnt/home || error_exit "Échec montage home"

            log "Montage data ${DISK}6 sur /mnt/data..."
            mount "${DISK}6" /mnt/data || error_exit "Échec montage data"
        else
            # UEFI avec home séparé
            log "Montage home ${DISK}4 sur /mnt/home..."
            mount "${DISK}4" /mnt/home || error_exit "Échec montage home"

            log "Montage data ${DISK}5 sur /mnt/data..."
            mount "${DISK}5" /mnt/data || error_exit "Échec montage data"
        fi
    else
        # Sans home séparée
        log "Montage data ${DISK}4 sur /mnt/data..."
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

# Configuration système dans chroot - CORRIGÉE
configure_system_enhanced() {
    log "=== CONFIGURATION SYSTÈME AVEC MENU DE REPARATION ==="
    
    local boot_mode="$BOOT_MODE"
    [[ -f /tmp/boot_mode ]] && boot_mode=$(cat /tmp/boot_mode)
    
    # Copie du script pour continuer en chroot
    cp "$0" /mnt/root/ 2>/dev/null || true
    cp "$LOG_FILE" /mnt/root/ 2>/dev/null || true
    echo "$boot_mode" > /mnt/root/boot_mode
    
    # Configuration en chroot avec menu de réparation
    arch-chroot /mnt /bin/bash << CHROOT_EOF
    
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
    
    # Installation et configuration GRUB avec menu de réparation
    pacman -S --noconfirm grub os-prober
    
    if [[ \$BOOT_MODE == "uefi" ]]; then
        echo "Configuration GRUB pour UEFI avec menu de réparation..."
        pacman -S --noconfirm efibootmgr
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable || {
            echo "Erreur: Échec installation GRUB UEFI, tentative avec --force..."
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable --force || {
                echo "Erreur: Échec installation GRUB UEFI"
                exit 1
            }
        }
    else
        echo "Configuration GRUB pour BIOS avec menu de réparation..."
        grub-install --target=i386-pc $DISK || {
            echo "Erreur: Échec installation GRUB BIOS"
            exit 1
        }
    fi
    
    # Configuration GRUB avec menu de réparation
    cat > /etc/default/grub << 'GRUB_CONFIG'
GRUB_DEFAULT=0
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="Arch Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_TIMEOUT_STYLE=menu
GRUB_DISABLE_SUBMENU=y
GRUB_DISABLE_RECOVERY=false
GRUB_DISABLE_OS_PROBER=false
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_CONFIG

    # Menu de réparation personnalisé
    mkdir -p /etc/grub.d
    cat > /etc/grub.d/40_custom_repair << 'REPAIR_MENU'
#!/bin/sh
exec tail -n +3 \$0

menuentry "=== MENU DE REPARATION SYSTEME ===" {
    echo "Menu de réparation disponible"
}

menuentry "Mode de récupération (Shell Root)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw init=/bin/bash
    initrd /boot/initramfs-linux.img
}

menuentry "Mode de récupération (Systemd)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw systemd.unit=rescue.target
    initrd /boot/initramfs-linux.img
}

menuentry "Mode console (sans GUI)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw systemd.unit=multi-user.target
    initrd /boot/initramfs-linux.img
}

menuentry "Vérification système de fichiers" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw fsck.mode=force
    initrd /boot/initramfs-linux.img
}
REPAIR_MENU

    chmod +x /etc/grub.d/40_custom_repair
    
    # Ajustement pour BIOS si nécessaire
    if [[ \$BOOT_MODE == "bios" ]]; then
        sed -i 's/hd0,gpt3/hd0,msdos3/' /etc/grub.d/40_custom_repair
    fi
    
    grub-mkconfig -o /boot/grub/grub.cfg || {
        echo "Erreur: Échec génération config GRUB"
        exit 1
    }
    
    # Installation des outils supplémentaires
    pacman -S --noconfirm iw wpa_supplicant dialog git reflector lshw unzip htop
    pacman -S --noconfirm wget pulseaudio alsa-utils alsa-plugins pavucontrol xdg-user-dirs
    
    # Configuration mot de passe root
    echo "Configuration du mot de passe root:"
    passwd
    
CHROOT_EOF
    
    log "Configuration système avec menu de réparation terminée"
}

# Installation environnement graphique
install_gui() {
    log "=== INSTALLATION ENVIRONNEMENT GRAPHIQUE ==="
    
    arch-chroot /mnt /bin/bash << 'CHROOT_EOF'
    
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
background = #2f343
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
# Installation manuelle de paquets supplémentaires
install_additional_packages() {
    log "=== INSTALLATION PAQUETS SUPPLEMENTAIRES ==="
    
    echo ""
    echo "=============================================================="
    echo "           INSTALLATION PAQUETS SUPPLEMENTAIRES              "
    echo "=============================================================="
    echo ""
    read -p "Voulez-vous installer des paquets supplémentaires? [y/N]: " install_extra
    
    if [[ $install_extra == [yY] ]]; then
        echo ""
        echo "Exemples de paquets populaires:"
        echo "- neofetch (info système)"
        echo "- discord (chat)"
        echo "- gimp (éditeur d'image)"
        echo "- libreoffice-fresh (suite bureautique)"
        echo "- code (Visual Studio Code)"
        echo "- docker (conteneurs)"
        echo "- steam (jeux)"
        echo "- obs-studio (streaming)"
        echo "- thunderbird (email)"
        echo "- telegram-desktop (messagerie)"
        echo ""
        
        while true; do
            echo "Entrez les noms des paquets à installer (séparés par des espaces):"
            echo "Ou tapez 'done' pour terminer, 'skip' pour annuler:"
            read -p "> " packages
            
            case $packages in
                "done"|"DONE")
                    log "Installation des paquets supplémentaires terminée"
                    break
                    ;;
                "skip"|"SKIP")
                    log "Installation des paquets supplémentaires annulée"
                    break
                    ;;
                "")
                    echo "Aucun paquet spécifié. Tapez 'done' pour terminer."
                    continue
                    ;;
                *)
                    log "Installation des paquets: $packages"
                    echo "Installation en cours..."
                    
                    # Installation des paquets
                    arch-chroot /mnt /bin/bash << CHROOT_EOF
                    pacman -S --noconfirm $packages || {
                        echo "Erreur lors de l'installation de certains paquets"
                        echo "Vérifiez que les noms des paquets sont corrects"
                    }
CHROOT_EOF
                    
                    echo "Installation terminée pour: $packages"
                    echo ""
                    echo "Voulez-vous installer d'autres paquets? (tapez 'done' pour terminer)"
                    ;;
            esac
        done
    else
        log "Installation des paquets supplémentaires ignorée"
    fi
}

# Version alternative avec menu de sélection
install_additional_packages_menu() {
    log "=== INSTALLATION PAQUETS SUPPLEMENTAIRES ==="
    
    echo ""
    echo "=============================================================="
    echo "           INSTALLATION PAQUETS SUPPLEMENTAIRES              "
    echo "=============================================================="
    echo ""
    read -p "Voulez-vous installer des paquets supplémentaires? [y/N]: " install_extra
    
    if [[ $install_extra == [yY] ]]; then
        local selected_packages=""
        
        while true; do
            echo ""
            echo "Catégories disponibles:"
            echo "1) Développement"
            echo "2) Multimédia"
            echo "3) Bureautique"
            echo "4) Jeux"
            echo "5) Internet/Communication"
            echo "6) Système/Utilitaires"
            echo "7) Installation manuelle (tapez les noms)"
            echo "8) Terminer et installer les paquets sélectionnés"
            echo "9) Annuler"
            echo ""
            echo "Paquets actuellement sélectionnés: $selected_packages"
            echo ""
            read -p "Votre choix [1-9]: " choice
            
            case $choice in
                1)
                    echo "Paquets de développement:"
                    echo "1) code (VS Code)  2) git  3) docker  4) nodejs  5) python  6) vim"
                    read -p "Sélectionnez (ex: 1 3 5): " dev_choice
                    for num in $dev_choice; do
                        case $num in
                            1) selected_packages="$selected_packages code" ;;
                            2) selected_packages="$selected_packages git" ;;
                            3) selected_packages="$selected_packages docker" ;;
                            4) selected_packages="$selected_packages nodejs npm" ;;
                            5) selected_packages="$selected_packages python python-pip" ;;
                            6) selected_packages="$selected_packages vim" ;;
                        esac
                    done
                    ;;
                2)
                    echo "Paquets multimédia:"
                    echo "1) gimp  2) obs-studio  3) audacity  4) blender  5) vlc"
                    read -p "Sélectionnez (ex: 1 3): " media_choice
                    for num in $media_choice; do
                        case $num in
                            1) selected_packages="$selected_packages gimp" ;;
                            2) selected_packages="$selected_packages obs-studio" ;;
                            3) selected_packages="$selected_packages audacity" ;;
                            4) selected_packages="$selected_packages blender" ;;
                            5) selected_packages="$selected_packages vlc" ;;
                        esac
                    done
                    ;;
                3)
                    echo "Paquets bureautique:"
                    echo "1) libreoffice-fresh  2) thunderbird  3) calibre"
                    read -p "Sélectionnez (ex: 1 2): " office_choice
                    for num in $office_choice; do
                        case $num in
                            1) selected_packages="$selected_packages libreoffice-fresh" ;;
                            2) selected_packages="$selected_packages thunderbird" ;;
                            3) selected_packages="$selected_packages calibre" ;;
                        esac
                    done
                    ;;
                4)
                    echo "Paquets jeux:"
                    echo "1) steam  2) lutris  3) wine"
                    read -p "Sélectionnez (ex: 1): " games_choice
                    for num in $games_choice; do
                        case $num in
                            1) selected_packages="$selected_packages steam" ;;
                            2) selected_packages="$selected_packages lutris" ;;
                            3) selected_packages="$selected_packages wine" ;;
                        esac
                    done
                    ;;
                5)
                    echo "Paquets internet/communication:"
                    echo "1) discord  2) telegram-desktop  3) firefox  4) chromium"
                    read -p "Sélectionnez (ex: 1 2): " comm_choice
                    for num in $comm_choice; do
                        case $num in
                            1) selected_packages="$selected_packages discord" ;;
                            2) selected_packages="$selected_packages telegram-desktop" ;;
                            3) selected_packages="$selected_packages firefox" ;;
                            4) selected_packages="$selected_packages chromium" ;;
                        esac
                    done
                    ;;
                6)
                    echo "Paquets système/utilitaires:"
                    echo "1) neofetch  2) tree  3) zip unzip  4) htop  5) nano"
                    read -p "Sélectionnez (ex: 1 3 4): " util_choice
                    for num in $util_choice; do
                        case $num in
                            1) selected_packages="$selected_packages neofetch" ;;
                            2) selected_packages="$selected_packages tree" ;;
                            3) selected_packages="$selected_packages zip unzip" ;;
                            4) selected_packages="$selected_packages htop" ;;
                            5) selected_packages="$selected_packages nano" ;;
                        esac
                    done
                    ;;
                7)
                    echo "Tapez les noms des paquets à ajouter (séparés par des espaces):"
                    read -p "> " manual_packages
                    selected_packages="$selected_packages $manual_packages"
                    ;;
                8)
                    if [[ -n "$selected_packages" ]]; then
                        log "Installation des paquets: $selected_packages"
                        echo "Installation en cours..."
                        
                        arch-chroot /mnt /bin/bash << CHROOT_EOF
                        pacman -S --noconfirm $selected_packages || {
                            echo "Erreur lors de l'installation de certains paquets"
                        }
CHROOT_EOF
                        
                        log "Installation terminée"
                    else
                        log "Aucun paquet sélectionné"
                    fi
                    break
                    ;;
                9)
                    log "Installation des paquets supplémentaires annulée"
                    break
                    ;;
                *)
                    echo "Choix invalide"
                    ;;
            esac
        done
    else
        log "Installation des paquets supplémentaires ignorée"
    fi
}

setup_user() {
    log "=== CONFIGURATION UTILISATEUR ==="
    
    # Création utilisateur et configuration sudo (sans passwd)
    arch-chroot /mnt /bin/bash << CHROOT_EOF
    
    # Création utilisateur
    useradd -m -g users -G wheel,storage,power,audio $USERNAME
    
    # Configuration sudo
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    
CHROOT_EOF
    
    # Configuration mot de passe utilisateur INTERACTIVE
    log "Configuration du mot de passe pour l'utilisateur $USERNAME:"
    echo "Configuration du mot de passe pour l'utilisateur $USERNAME:"
    arch-chroot /mnt passwd $USERNAME
    
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
#!/bin/bash

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
install_grub_with_repair() {
    local boot_mode="$1"
    
    log "=== INSTALLATION GRUB AVEC MENU DE REPARATION ==="
    
    # Installation des paquets GRUB nécessaires
    pacman -S --noconfirm grub os-prober
    
    if [[ $boot_mode == "uefi" ]]; then
        log "Configuration GRUB pour UEFI avec menu de réparation..."
        pacman -S --noconfirm efibootmgr
        
        # Installation GRUB UEFI
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable || {
            log "Erreur: Échec installation GRUB UEFI, tentative avec --force..."
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable --force || {
                error_exit "Échec installation GRUB UEFI"
            }
        }
    else
        log "Configuration GRUB pour BIOS avec menu de réparation..."
        
        # Installation GRUB BIOS
        grub-install --target=i386-pc $DISK || {
            error_exit "Échec installation GRUB BIOS"
        }
    fi
    
    # Configuration GRUB personnalisée avec menu de réparation
    configure_grub_repair_menu
    
    # Génération de la configuration GRUB
    grub-mkconfig -o /boot/grub/grub.cfg || {
        error_exit "Échec génération config GRUB"
    }
    
    log_success "GRUB avec menu de réparation installé"
}

# Configuration du menu de réparation GRUB
configure_grub_repair_menu() {
    log "Configuration du menu de réparation GRUB..."
    
    # Configuration /etc/default/grub pour le menu de réparation
    cat > /etc/default/grub << 'GRUB_CONFIG'
# GRUB Configuration avec menu de réparation
GRUB_DEFAULT=0
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="Arch Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""

# Affichage du menu même si un seul OS
GRUB_TIMEOUT_STYLE=menu
GRUB_DISABLE_SUBMENU=y

# Activation des options de réparation
GRUB_DISABLE_RECOVERY=false

# Détection automatique des autres OS
GRUB_DISABLE_OS_PROBER=false

# Résolution de l'écran
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_CONFIG

    # Création du menu de réparation personnalisé
    mkdir -p /etc/grub.d
    
    # Script de menu de réparation personnalisé
    cat > /etc/grub.d/40_custom_repair << 'REPAIR_MENU'
#!/bin/sh
exec tail -n +3 $0

menuentry "=== MENU DE REPARATION SYSTEME ===" {
    echo "Menu de réparation - Sélectionnez une option ci-dessous"
}

menuentry "Mode de récupération (Shell Root)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw init=/bin/bash
    initrd /boot/initramfs-linux.img
}

menuentry "Mode de récupération (Systemd)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw systemd.unit=rescue.target
    initrd /boot/initramfs-linux.img
}

menuentry "Mode console (sans GUI)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw systemd.unit=multi-user.target
    initrd /boot/initramfs-linux.img
}

menuentry "Mode diagnostic (verbose)" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw debug systemd.log_level=debug
    initrd /boot/initramfs-linux.img
}

menuentry "Vérification système de fichiers" {
    set root='hd0,gpt3'
    linux /boot/vmlinuz-linux root=/dev/sda3 rw fsck.mode=force
    initrd /boot/initramfs-linux.img
}

menuentry "Arrêter le système" {
    halt
}

menuentry "Redémarrer le système" {
    reboot
}
REPAIR_MENU

    chmod +x /etc/grub.d/40_custom_repair
    
    # Configuration pour UEFI/BIOS
    if [[ -d /sys/firmware/efi/efivars ]]; then
        # Configuration UEFI (déjà correcte)
        true
    else
        # Configuration BIOS
        sed -i 's/hd0,gpt3/hd0,msdos3/' /etc/grub.d/40_custom_repair
    fi
    
    log_success "Menu de réparation GRUB configuré"
}

# Fonction principale
main() {
    log "=== DEBUT DE L'INSTALLATION ARCH LINUX (UEFI/BIOS) ==="
    log "Fichier de log: $LOG_FILE"

    # Ces fonctions s'exécutent dans l'ordre pour tout le monde :
    check_prerequisites          # Vérification internet, disque, etc.
    partition_menu              # Affichage du menu et gestion du choix utilisateur
    prepare_disk_for_format     # Préparation du disque pour formatage
    format_partitions           # Formatage des partitions
    mount_partitions            # Montage des partitions
    install_base                # Installation du système de base
    #configure_system            # Configuration des paramètres système
    configure_system_enhanced() # Configuration des paramètres système avancées
    install_gui                 # Installation de l'environnement graphique
    install_additional_packages # Ajout paquets additionnels cli
    install_additional_packages_menu  # Ajout paquets additionnels menu
    setup_user                  # Création du compte utilisateur
    create_post_install_script  # Création du script post-installation

    # Message final et nettoyage
    log "=== INSTALLATION TERMINEE ==="
    echo ""
    echo "=============================================================="
    echo "                  INSTALLATION TERMINEE                      "
    echo "=============================================================="
    echo "  Mode de boot: $BOOT_MODE"
    echo "  1. Redémarrez le système: reboot                           "
    echo "  2. Connectez-vous avec l'utilisateur: $USERNAME           "
    echo "  3. Exécutez le script post-installation:                   "
    echo "     ./post_install.sh                                       "
    echo "                                                              "
    echo "  Log sauvegardé dans: /root/arch_install.log                 "
    echo "  N'oubliez pas de donner une étoile sur GitHub !             "
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
# Point d'entrée du script, compatible Bash et Zsh
if [[ -n "$ZSH_VERSION" ]]; then
    # Zsh : on vérifie le contexte pour ne pas lancer si script est "sourcé"
    if [[ $ZSH_EVAL_CONTEXT == *:file ]]; then
        main "$@"
    fi
else
    # Bash (ou autre) : on lance direct
    main "$@"
fi
