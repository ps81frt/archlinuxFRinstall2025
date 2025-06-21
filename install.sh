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
HOSTNAME="archlinux"
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
# Détection automatique du disque principal - CORRIGÉE
detect_main_disk() {
    log "=== DÉTECTION DU DISQUE PRINCIPAL ==="
    
    # Liste des disques disponibles
    local disks=($(lsblk -dn -o NAME,SIZE,TYPE | grep "disk" | awk '{print "/dev/"$1}'))
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        error_exit "Aucun disque détecté"
    elif [[ ${#disks[@]} -eq 1 ]]; then
        DISK="${disks[0]}"
        log_success "Disque unique détecté: $DISK"
    else
        log "Plusieurs disques détectés:"
        lsblk -dn -o NAME,SIZE,TYPE | grep "disk" | nl
        echo ""
        read -p "Choisissez le numéro du disque à utiliser: " choice
        
        if [[ $choice -ge 1 && $choice -le ${#disks[@]} ]]; then
            DISK="${disks[$((choice-1))]}"
            log_success "Disque sélectionné: $DISK"
        else
            error_exit "Choix invalide"
        fi
    fi
    
    # Vérification existence du disque
    if [[ ! -b "$DISK" ]]; then
        error_exit "Disque $DISK non trouvé"
    fi
}

# Fonction de vérification des prérequis
# Fonction de vérification des prérequis - CORRIGÉE
check_prerequisites() {
    log "=== VERIFICATION DES PREREQUIS ==="
    
    # Vérification des droits root
    if [[ $EUID -ne 0 ]]; then
        error_exit "Ce script doit être exécuté en tant que root"
    fi
    
    # Vérification connexion internet avec timeout
    log "Vérification de la connexion internet..."
    if ! timeout 10 ping -c 3 8.8.8.8 &> /dev/null; then
        log_warning "Test avec 8.8.8.8 échoué, test avec 1.1.1.1..."
        if ! timeout 10 ping -c 3 1.1.1.1 &> /dev/null; then
            error_exit "Pas de connexion internet détectée"
        fi
    fi
    log_success "Connexion internet OK"
    
    # Détection du mode de boot
    detect_boot_mode
    
    # Détection automatique du disque
    detect_main_disk
    
    # Configuration clavier français
    loadkeys fr || log_warning "Impossible de charger le clavier français"
    log_success "Configuration des prérequis terminée"
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
# Partitionnement UEFI (GPT) - CORRIGÉ
partition_uefi() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6
    
    log "Partitionnement UEFI/GPT sur $disk..."
    
    # Nettoyage complet du disque
    wipefs -af "$disk" || true
    sgdisk --zap-all "$disk" || error_exit "Échec du nettoyage du disque"
    
    # Attendre que les changements soient pris en compte
    sleep 5
    partprobe "$disk" 2>/dev/null || true
    
    # Création des partitions avec sgdisk
    if [[ $has_separate_home == false ]]; then
        # Configuration sans partition home séparée (4 partitions)
        log "Création des partitions (sans /home séparé)..."
        sgdisk --clear \
               --new=1:0:+$boot_size --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$swap_size --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$root_size --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:0 --typecode=4:8300 --change-name=4:'Linux data' \
               "$disk" || error_exit "Échec de la création des partitions"
    else
        # Configuration complète avec partition home (5 partitions)
        log "Création des partitions (avec /home séparé)..."
        sgdisk --clear \
               --new=1:0:+$boot_size --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$swap_size --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$root_size --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:+$home_size --typecode=4:8302 --change-name=4:'Linux home' \
               --new=5:0:0 --typecode=5:8300 --change-name=5:'Linux data' \
               "$disk" || error_exit "Échec de la création des partitions"
    fi
    
    # Attendre et forcer la reconnaissance des partitions
    sleep 5
    partprobe "$disk" 2>/dev/null || true
    udevadm settle
    
    # Vérifier que les partitions ont été créées
    if ! lsblk "$disk" | grep -q "${disk##*/}1"; then
        error_exit "Les partitions n'ont pas été créées correctement"
    fi
    
    log_success "Partitions UEFI créées avec succès"
}

# Partitionnement BIOS (MBR) - CORRIGÉ
partition_bios() {
    local disk=$1
    local boot_size=$2
    local swap_size=$3
    local root_size=$4
    local home_size=$5
    local has_separate_home=$6

    log "Partitionnement BIOS sur $disk"

    # Nettoyage des partitions existantes
    parted "$disk" --script mklabel msdos

    # Crée boot
    parted "$disk" --script mkpart primary ext4 1MiB "$boot_size"
    mkfs.ext4 "${disk}1"

    # Crée swap
    parted "$disk" --script mkpart primary linux-swap "$boot_size" "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) ))"
    mkswap "${disk}2"

    # Crée root
    parted "$disk" --script mkpart primary ext4 "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) ))" "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) + $(numfmt --from=iec $root_size) ))"
    mkfs.ext4 "${disk}3"

    # Crée partition étendue pour home + data
    parted "$disk" --script mkpart extended "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) + $(numfmt --from=iec $root_size) ))" 100%

    if [[ $has_separate_home == true ]]; then
        # home en logique sda5
        parted "$disk" --script mkpart logical ext4 "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) + $(numfmt --from=iec $root_size) ))" "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) + $(numfmt --from=iec $root_size) + $(numfmt --from=iec $home_size) ))"
        mkfs.ext4 "${disk}5"

        # data en logique sda6 (reste)
        parted "$disk" --script mkpart logical ext4 "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) + $(numfmt --from=iec $root_size) + $(numfmt --from=iec $home_size) ))" 100%
        mkfs.ext4 "${disk}6"
    else
        # data en logique sda5 (reste)
        parted "$disk" --script mkpart logical ext4 "$(( $(numfmt --from=iec $boot_size) + $(numfmt --from=iec $swap_size) + $(numfmt --from=iec $root_size) ))" 100%
        mkfs.ext4 "${disk}5"
    fi

    log "Partitionnement BIOS terminé"
}



# Fonction de partitionnement manuel - CORRIGÉE
# Partitionnement BIOS (MBR) - CORRIGÉ
partition_bios() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6
    
    log "Partitionnement BIOS/MBR sur $disk..."
    
    # Nettoyage complet du disque
    wipefs -af "$disk" || true
    dd if=/dev/zero of="$disk" bs=512 count=2048 2>/dev/null || true
    
    sleep 3
    
    # Simplification: toujours utiliser 4 partitions primaires max
    if [[ $has_separate_home == false ]]; then
        # Configuration sans partition home séparée (4 partitions primaires)
        log "Création des partitions MBR (sans /home séparé)..."
        cat << EOF | fdisk "$disk"
o
n
p
1

+$boot_size
a
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
        # Configuration avec home - utilisation d'une partition étendue
        log "Création des partitions MBR (avec /home séparé)..."
        cat << EOF | fdisk "$disk"
o
n
p
1

+$boot_size
a
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
    
    # Attendre et forcer la reconnaissance des partitions
    sleep 5
    partprobe "$disk" 2>/dev/null || true
    udevadm settle
    
    # Vérifier que les partitions ont été créées
    if ! lsblk "$disk" | grep -q "${disk##*/}1"; then
        error_exit "Les partitions n'ont pas été créées correctement"
    fi
    
    log_success "Partitions BIOS créées avec succès"
}

# Menu de choix du partitionnement
# Enhanced partition menu with GRUB repair option
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
    echo "4) Réparation GRUB (système déjà installé)"
    echo ""
    read -p "Votre choix [1-4]: " choice
    
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
            log_info "Partitionnement ignoré. Veuillez indiquer les partitions existantes."

            read -p "Partition boot (ex: /dev/sda1 ou /dev/nvme0n1p1) : " BOOT_PART
            read -p "Partition swap (ex: /dev/sda2 ou /dev/nvme0n1p2) : " SWAP_PART
            read -p "Partition root (ex: /dev/sda3 ou /dev/nvme0n1p3) : " ROOT_PART

            read -p "Avez-vous une partition /home séparée ? (y/n) : " home_sep
            if [[ $home_sep =~ ^[Yy]$ ]]; then
                HAS_SEPARATE_HOME=true
                read -p "Partition /home (ex: /dev/sda4 ou /dev/nvme0n1p4) : " HOME_PART
                read -p "Partition /data (ex: /dev/sda5 ou /dev/nvme0n1p5) : " DATA_PART
            else
                HAS_SEPARATE_HOME=false
                read -p "Partition /data (ex: /dev/sda4 ou /dev/nvme0n1p4) : " DATA_PART
                HOME_PART=""
            fi

            echo "$HAS_SEPARATE_HOME" > /tmp/has_separate_home
            echo "$BOOT_MODE" > /tmp/boot_mode

            echo "$BOOT_PART" > /tmp/boot_part
            echo "$SWAP_PART" > /tmp/swap_part
            echo "$ROOT_PART" > /tmp/root_part
            echo "$HOME_PART" > /tmp/home_part
            echo "$DATA_PART" > /tmp/data_part
    ;;


        4)
            log_info "Mode réparation GRUB sélectionné"
            grub_repair_mode
            exit 0
            ;;
        *)
            log_warning "Choix invalide, partitionnement automatique par défaut"
            auto_partition "$DISK"
            ;;
    esac
}

# Fonction de réparation GRUB
grub_repair_mode() {
    log "=== MODE REPARATION GRUB ==="
    
    echo ""
    echo "=============================================================="
    echo "                  MODE REPARATION GRUB                       "
    echo "=============================================================="
    echo "Ce mode permet de réparer GRUB sur un système déjà installé"
    echo ""
    
    # Affichage des disques disponibles
    echo "Disques disponibles:"
    lsblk -d -n -o NAME,SIZE,MODEL | grep -E '^[s|n|v]d[a-z]|^mmcblk[0-9]' | while read line; do
        echo "  /dev/$line"
    done
    echo ""
    
    # Sélection du disque
    read -p "Entrez le disque principal (ex: /dev/sda): " REPAIR_DISK
    
    if [[ ! -b "$REPAIR_DISK" ]]; then
        error_exit "Disque $REPAIR_DISK non trouvé"
    fi
    
    log "Disque sélectionné: $REPAIR_DISK"
    
    # Affichage des partitions
    echo ""
    echo "Partitions disponibles sur $REPAIR_DISK:"
    lsblk "$REPAIR_DISK"
    echo ""
    
    # Sélection de la partition root
    read -p "Entrez la partition root (ex: ${REPAIR_DISK}3): " ROOT_PARTITION
    
    if [[ ! -b "$ROOT_PARTITION" ]]; then
        error_exit "Partition $ROOT_PARTITION non trouvée"
    fi
    
    # Sélection de la partition boot
    if [[ $BOOT_MODE == "uefi" ]]; then
        read -p "Entrez la partition EFI (ex: ${REPAIR_DISK}1): " BOOT_PARTITION
    else
        read -p "Entrez la partition boot (ex: ${REPAIR_DISK}1): " BOOT_PARTITION
    fi
    
    if [[ ! -b "$BOOT_PARTITION" ]]; then
        error_exit "Partition boot $BOOT_PARTITION non trouvée"
    fi
    
    log "Partition root: $ROOT_PARTITION"
    log "Partition boot: $BOOT_PARTITION"
    
    # Confirmation
    echo ""
    echo "Configuration détectée:"
    echo "  Mode de boot: $BOOT_MODE"
    echo "  Disque: $REPAIR_DISK"
    echo "  Partition root: $ROOT_PARTITION"
    echo "  Partition boot: $BOOT_PARTITION"
    echo ""
    read -p "Continuer avec la réparation GRUB? [y/N]: " confirm
    
    if [[ $confirm != [yY] ]]; then
        log "Réparation GRUB annulée"
        exit 0
    fi
    
    # Début de la réparation
    repair_grub_system "$REPAIR_DISK" "$ROOT_PARTITION" "$BOOT_PARTITION"
}

# Fonction de réparation du système GRUB
repair_grub_system() {
    local disk=$1
    local root_part=$2
    local boot_part=$3
    
    log "=== REPARATION GRUB EN COURS ==="
    
    # Démontage préventif
    umount -R /mnt 2>/dev/null || true
    
    # Montage de la partition root
    log "Montage de la partition root $root_part..."
    mount "$root_part" /mnt || error_exit "Impossible de monter $root_part"
    
    # Montage de la partition boot
    log "Montage de la partition boot $boot_part..."
    mkdir -p /mnt/boot
    mount "$boot_part" /mnt/boot || error_exit "Impossible de monter $boot_part"
    
    # Montage des pseudo-systèmes de fichiers
    log "Montage des pseudo-systèmes de fichiers..."
    mount --types proc /proc /mnt/proc || error_exit "Échec montage /proc"
    mount --rbind /sys /mnt/sys || error_exit "Échec montage /sys"
    mount --make-rslave /mnt/sys
    mount --rbind /dev /mnt/dev || error_exit "Échec montage /dev"
    mount --make-rslave /mnt/dev
    
    # Réparation GRUB en chroot
    log "Réparation GRUB en chroot..."
    
    arch-chroot /mnt /bin/bash << CHROOT_REPAIR_EOF
    
    echo "=== Réparation GRUB en cours ==="
    
    # Vérification de la connectivité réseau pour les mises à jour
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo "Mise à jour des paquets GRUB..."
        pacman -Sy grub --noconfirm
        
        if [[ "$BOOT_MODE" == "uefi" ]]; then
            pacman -S --noconfirm efibootmgr
        fi
    else
        echo "Pas de réseau - utilisation des paquets existants"
    fi
    
    # Réinstallation de GRUB
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        echo "Réinstallation GRUB UEFI..."
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck || {
            echo "ERREUR: Échec de l'installation GRUB UEFI"
            exit 1
        }
    else
        echo "Réinstallation GRUB BIOS..."
        grub-install --target=i386-pc "$disk" --recheck || {
            echo "ERREUR: Échec de l'installation GRUB BIOS"
            exit 1
        }
    fi
    
    # Régénération de la configuration GRUB
    echo "Régénération de la configuration GRUB..."
    grub-mkconfig -o /boot/grub/grub.cfg || {
        echo "ERREUR: Échec de la génération de la configuration GRUB"
        exit 1
    }
    
    # Ajout d'entrées de réparation personnalisées
    echo "Ajout d'entrées de réparation au menu GRUB..."
    
    cat >> /etc/grub.d/40_custom << 'REPAIR_ENTRIES'
#!/bin/sh
exec tail -n +3 \$0

menuentry 'Arch Linux - Mode Réparation' --class arch --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root
    linux /boot/vmlinuz-linux root=PARTUUID=AUTO rw systemd.unit=rescue.target
    initrd /boot/initramfs-linux.img
}

menuentry 'Arch Linux - Shell de Récupération' --class arch --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root
    linux /boot/vmlinuz-linux root=PARTUUID=AUTO rw init=/bin/bash
    initrd /boot/initramfs-linux.img
}
REPAIR_ENTRIES

    chmod +x /etc/grub.d/40_custom
    
    # Régénération finale
    grub-mkconfig -o /boot/grub/grub.cfg
    
    echo "=== Réparation GRUB terminée avec succès ==="
    
CHROOT_REPAIR_EOF
    
    # Vérification du succès
    if [[ $? -eq 0 ]]; then
        log_success "Réparation GRUB terminée avec succès"
    else
        error_exit "Échec de la réparation GRUB"
    fi
    
    # Démontage
    log "Démontage des partitions..."
    umount -R /mnt 2>/dev/null || true
    
    # Message final
    echo ""
    echo "=============================================================="
    echo "                REPARATION GRUB TERMINEE                     "
    echo "=============================================================="
    echo "  GRUB a été réparé avec succès sur $disk"
    echo ""
    echo "  Entrées ajoutées au menu GRUB:"
    echo "  - Arch Linux (démarrage normal)"
    echo "  - Arch Linux - Mode Réparation"
    echo "  - Arch Linux - Shell de Récupération"
    echo ""
    echo "  Vous pouvez maintenant redémarrer le système."
    echo "=============================================================="
    echo ""
    
    read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_confirm
    if [[ $reboot_confirm == [yY] ]]; then
        log "Redémarrage du système..."
        reboot
    else
        log "Redémarrage annulé. Tapez 'reboot' pour redémarrer manuellement."
    fi
}

# Fonction de réparation GRUB rapide (utilitaire)
quick_grub_repair() {
    echo "=== REPARATION GRUB RAPIDE ==="
    
    # Auto-détection des partitions
    ROOT_PART=$(findmnt -n -o SOURCE /)
    BOOT_PART=$(findmnt -n -o SOURCE /boot)
    
    if [[ -z "$ROOT_PART" ]]; then
        echo "Impossible de détecter la partition root"
        return 1
    fi
    
    echo "Partition root détectée: $ROOT_PART"
    echo "Partition boot détectée: $BOOT_PART"
    
    # Réinstallation GRUB
    if [[ -d /sys/firmware/efi/efivars ]]; then
        echo "Mode UEFI détecté"
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
    else
        echo "Mode BIOS détecté"
        DISK=$(lsblk -no PKNAME "$ROOT_PART" | head -1)
        grub-install --target=i386-pc "/dev/$DISK" --recheck
    fi
    
    # Régénération config
    grub-mkconfig -o /boot/grub/grub.cfg
    
    echo "Réparation GRUB rapide terminée"
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
    log "Disque utilisé : $DISK"

    # Attendre que les partitions soient reconnues
    sleep 3
    udevadm settle

    # Fonction helper pour attendre qu'une partition existe
    wait_for_partition() {
        local part=$1
        local count=0
        while [[ ! -b "$part" && $count -lt 30 ]]; do
            sleep 1
            ((count++))
        done
        if [[ ! -b "$part" ]]; then
            error_exit "Partition $part non trouvée après 30 secondes"
        fi
    }

    # Formatage partition de démarrage selon mode
    wait_for_partition "${DISK}1"
    if [[ $boot_mode == "uefi" ]]; then
        log "Formatage de la partition EFI ${DISK}1..."
        mkfs.fat -F32 -n "EFI" "${DISK}1" || error_exit "Échec formatage EFI"
    else
        log "Formatage de la partition /boot ${DISK}1..."
        mkfs.ext4 -F -L "BOOT" "${DISK}1" || error_exit "Échec formatage /boot"
    fi

    # Swap
    wait_for_partition "${DISK}2"
    log "Configuration du swap ${DISK}2..."
    mkswap -L "SWAP" "${DISK}2" || error_exit "Échec configuration swap"

    # Root
    wait_for_partition "${DISK}3"
    log "Formatage de la partition root ${DISK}3..."
    mkfs.ext4 -F -L "ROOT" "${DISK}3" || error_exit "Échec formatage root"

    # Home et data selon configuration
    if [[ $has_separate_home == "true" ]]; then
        if [[ $boot_mode == "bios" ]]; then
            # En BIOS avec home séparé: partitions logiques
            wait_for_partition "${DISK}5"
            log "Formatage home ${DISK}5..."
            mkfs.ext4 -F -L "HOME" "${DISK}5" || error_exit "Échec formatage home"

            wait_for_partition "${DISK}6"
            log "Formatage data ${DISK}6..."
            mkfs.ext4 -F -L "DATA" "${DISK}6" || error_exit "Échec formatage data"
        else
            # En UEFI avec home séparé: partitions 4 et 5
            wait_for_partition "${DISK}4"
            log "Formatage home ${DISK}4..."
            mkfs.ext4 -F -L "HOME" "${DISK}4" || error_exit "Échec formatage home"

            wait_for_partition "${DISK}5"
            log "Formatage data ${DISK}5..."
            mkfs.ext4 -F -L "DATA" "${DISK}5" || error_exit "Échec formatage data"
        fi
    else
        # Sans home séparée
        wait_for_partition "${DISK}4"
        log "Formatage data ${DISK}4 (pas de home séparé)..."
        mkfs.ext4 -F -L "DATA" "${DISK}4" || error_exit "Échec formatage data"
    fi

    log_success "Formatage terminé"
}
# Montage des partitions - CORRIGÉ
# Montage des partitions - CORRIGÉ
mount_partitions() {
    log "=== MONTAGE DES PARTITIONS ==="

    local has_separate_home="true"
    local boot_mode="$BOOT_MODE"

    [[ -f /tmp/has_separate_home ]] && has_separate_home=$(cat /tmp/has_separate_home)
    [[ -f /tmp/boot_mode ]] && boot_mode=$(cat /tmp/boot_mode)

    log "Mode de boot : $boot_mode"
    log "Partition /home séparée : $has_separate_home"

    # Démonter tout ce qui pourrait être monté
    umount -R /mnt 2>/dev/null || true

    # Montage root en premier
    log "Montage root ${DISK}3 sur /mnt..."
    mount "${DISK}3" /mnt || error_exit "Échec montage root"

    # Activation swap
    log "Activation swap ${DISK}2..."
    swapon "${DISK}2" || error_exit "Échec activation swap"

    # Création des points de montage nécessaires
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

    log_success "Montage terminé"
    log "État des montages:"
    lsblk | grep -E "(NAME|${DISK##*/})"
}




# Installation de base
# Installation de base - CORRIGÉE
# Installation de base - CORRIGÉE
install_base() {
    log "=== INSTALLATION DE BASE ==="
    
    # Synchronisation de l'horloge
    log "Synchronisation de l'horloge..."
    timedatectl set-ntp true
    sleep 2
    
    # Mise à jour des miroirs avec gestion d'erreur
    log "Mise à jour des miroirs pour la France..."
    if command -v reflector &> /dev/null; then
        reflector --country France --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || {
            log_warning "Reflector a échoué, utilisation des miroirs par défaut"
        }
    else
        log_warning "Reflector non disponible, installation..."
        pacman -Sy --noconfirm reflector || log_warning "Impossible d'installer reflector"
        reflector --country France --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || {
            log_warning "Reflector a échoué, utilisation des miroirs par défaut"
        }
    fi
    
    # Mise à jour de la base de données des paquets
    log "Mise à jour de la base de données pacman..."
    pacman -Sy || error_exit "Échec de la mise à jour de pacman"
    
    # Installation des paquets de base avec gestion d'erreur
    log "Installation des paquets de base..."
    local base_packages="base base-devel linux linux-firmware vim openssh"
    
    # Détection du processeur pour le microcode
    if lscpu | grep -qi intel; then
        base_packages="$base_packages intel-ucode"
        log "Processeur Intel détecté, ajout d'intel-ucode"
    elif lscpu | grep -qi amd; then
        base_packages="$base_packages amd-ucode"
        log "Processeur AMD détecté, ajout d'amd-ucode"
    fi
    
    # Installation avec retry en cas d'échec
    local retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        if pacstrap /mnt $base_packages; then
            break
        else
            ((retry_count++))
            log_warning "Échec de l'installation (tentative $retry_count/3), nouvelle tentative..."
            sleep 5
        fi
    done
    
    if [[ $retry_count -eq 3 ]]; then
        error_exit "Échec de l'installation de base après 3 tentatives"
    fi
    
    # Génération du fstab avec vérification
    log "Génération du fstab..."
    genfstab -U /mnt > /mnt/etc/fstab || error_exit "Échec génération fstab"
    
    # Vérification du fstab généré
    if [[ ! -s /mnt/etc/fstab ]]; then
        error_exit "Le fichier fstab est vide"
    fi
    
    log "Contenu du fstab généré:"
    cat /mnt/etc/fstab
    
    log_success "Installation de base terminée"
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
    #echo "Configuration du mot de passe root:"
    #passwd
    
CHROOT_EOF
    
    log "Configuration système avec menu de réparation terminée"
}

# Installation environnement graphique
# Installation environnement graphique - CORRIGÉE
install_gui() {
    log "=== INSTALLATION ENVIRONNEMENT GRAPHIQUE ==="
    
    arch-chroot /mnt /bin/bash << 'CHROOT_EOF'
set -e

echo "Installation de l'environnement graphique..."

# Installation serveur X avec gestion d'erreur
echo "Installation du serveur X..."
if ! pacman -S --noconfirm xorg-server xorg-apps xorg-xinit; then
    echo "Erreur: Échec installation serveur X"
    exit 1
fi

# Installation i3 window manager
echo "Installation de i3..."
if ! pacman -S --noconfirm i3-wm i3blocks i3lock i3status numlockx; then
    echo "Attention: Installation partielle de i3"
fi

# Installation gestionnaire de connexion
echo "Installation du gestionnaire de connexion..."
if pacman -S --noconfirm lightdm lightdm-gtk-greeter; then
    systemctl enable lightdm.service || echo "Attention: lightdm pas activé"
else
    echo "Attention: Échec installation lightdm"
fi

# Installation polices essentielles
echo "Installation des polices..."
local font_packages="ttf-dejavu ttf-liberation noto-fonts"
pacman -S --noconfirm $font_packages || echo "Attention: Polices partiellement installées"

# Applications de base
echo "Installation des applications de base..."
local base_apps="firefox konsole ranger rofi dmenu"
pacman -S --noconfirm $base_apps || echo "Attention: Applications partiellement installées"

# Lecteur multimédia
pacman -S --noconfirm vlc || echo "Attention: VLC non installé"

# Thèmes et apparence
echo "Installation des thèmes..."
local theme_packages="lxappearance arc-gtk-theme papirus-icon-theme"
pacman -S --noconfirm $theme_packages || echo "Attention: Thèmes partiellement installés"

# Configuration thème lightdm si installé
if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]]; then
    cat > /etc/lightdm/lightdm-gtk-greeter.conf << EOF
[greeter]
theme-name = Arc-Dark
icon-theme-name = Papirus-Dark
background = #2f343f
EOF
fi

# Gestion de l'alimentation et optimisations
echo "Installation des outils de gestion d'énergie..."
local power_packages="tlp powertop acpi"
if pacman -S --noconfirm $power_packages; then
    systemctl enable tlp.service || echo "Attention: TLP pas activé"
    systemctl mask systemd-rfkill.service systemd-rfkill.socket || true
fi

# Bluetooth
echo "Installation du support Bluetooth..."
local bluetooth_packages="bluez bluez-utils"
if pacman -S --noconfirm $bluetooth_packages; then
    systemctl enable bluetooth.service || echo "Attention: Bluetooth pas activé"
fi

# Support audio avancé
echo "Installation du support audio..."
pacman -S --noconfirm pavucontrol || echo "Attention: pavucontrol non installé"

# Optimisation SSD
echo "Activation du trim automatique..."
systemctl enable fstrim.timer || echo "Attention: fstrim.timer pas activé"

echo "Installation GUI terminée"

CHROOT_EOF

    if [[ $? -ne 0 ]]; then
        log_warning "Installation GUI partiellement échouée, mais on continue"
    else
        log_success "Installation GUI terminée"
    fi
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


# Nettoyage final
cleanup() {
    log "=== NETTOYAGE FINAL ==="
    
    # Synchronisation des données
    sync
    
    # Démontage des partitions dans l'ordre inverse
    log "Démontage des partitions..."
    
    # Démontage récursif avec retry
    local retry_count=0
    while [[ $retry_count -lt 5 ]]; do
        if umount -R /mnt 2>/dev/null; then
            log_success "Partitions démontées"
            break
        else
            ((retry_count++))
            log_warning "Tentative de démontage $retry_count/5..."
            sleep 2
            
            # Forcer la fermeture des processus utilisant /mnt
            fuser -km /mnt 2>/dev/null || true
            sleep 1
        fi
    done
    
    if [[ $retry_count -eq 5 ]]; then
        log_warning "Impossible de démonter proprement, démontage forcé"
        umount -fl /mnt 2>/dev/null || true
    fi
    
    # Désactivation du swap
    log "Désactivation du swap..."
    swapoff "${DISK}2" 2>/dev/null || log_warning "Swap déjà désactivé"
    
    # Nettoyage des fichiers temporaires
    log "Nettoyage des fichiers temporaires..."
    rm -f /tmp/has_separate_home /tmp/boot_mode
    
    # Sauvegarde du log
    cp "$LOG_FILE" "/tmp/arch_install_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null || true
    
    log_success "Nettoyage terminé"
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

# Configuration manuelle du mot de passe root
setup_root_password() {
    log "=== CONFIGURATION MOT DE PASSE ROOT ==="
    
    echo ""
    echo "=============================================================="
    echo "           CONFIGURATION DU MOT DE PASSE ROOT                "
    echo "=============================================================="
    echo "Vous allez maintenant définir le mot de passe root"
    echo "Tapez votre mot de passe quand demandé"
    echo ""
    
    # Utilisation de script expect pour automatiser l'interaction
    arch-chroot /mnt /bin/bash -c "passwd" || {
        log "Première tentative échouée, nouvelle tentative..."
        arch-chroot /mnt /bin/bash -c "passwd"
    }
    
    log_success "Mot de passe root configuré"
}


# FONCTION CORRIGÉE : Configuration utilisateur
setup_user() {
    log "=== CONFIGURATION UTILISATEUR ==="
    
    cat > /mnt/root/user_config.sh << USER_SCRIPT
#!/bin/bash

# Création utilisateur
useradd -m -g users -G wheel,storage,power,audio $USERNAME

# Configuration sudo
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

USER_SCRIPT
    
    chmod +x /mnt/root/user_config.sh
    arch-chroot /mnt /root/user_config.sh || error_exit "Échec création utilisateur"
    
    log "Utilisateur $USERNAME créé"
}

setup_user_password() {
    log "=== CONFIGURATION MOT DE PASSE UTILISATEUR ==="
    
    echo ""
    echo "=============================================================="
    echo "      CONFIGURATION DU MOT DE PASSE UTILISATEUR $USERNAME    "
    echo "=============================================================="
    echo "Vous allez maintenant définir le mot de passe pour $USERNAME"
    echo "Tapez votre mot de passe quand demandé"
    echo ""
    
    # Configuration du mot de passe utilisateur
    arch-chroot /mnt /bin/bash -c "passwd $USERNAME" || {
        log "Première tentative échouée, nouvelle tentative..."
        arch-chroot /mnt /bin/bash -c "passwd $USERNAME"
    }
    
    log_success "Mot de passe utilisateur configuré"
}

configure_system() {
    log "=== CONFIGURATION SYSTÈME ==="
    
    local boot_mode="$BOOT_MODE"
    [[ -f /tmp/boot_mode ]] && boot_mode=$(cat /tmp/boot_mode)
    
    # Copie du script pour continuer en chroot
    cp "$0" /mnt/root/ 2>/dev/null || true
    cp "$LOG_FILE" /mnt/root/ 2>/dev/null || true
    echo "$boot_mode" > /mnt/root/boot_mode
    
    # Configuration en chroot
    cat > /mnt/root/chroot_config.sh << 'CHROOT_SCRIPT'
#!/bin/bash

# Lecture du mode de boot
BOOT_MODE=$(cat /root/boot_mode 2>/dev/null || echo "uefi")

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

if [[ $BOOT_MODE == "uefi" ]]; then
    echo "Configuration GRUB pour UEFI..."
    pacman -S --noconfirm efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB || {
        echo "Erreur: Échec installation GRUB UEFI"
        exit 1
    }
else
    echo "Configuration GRUB pour BIOS..."
    grub-install --target=i386-pc $DISK || {
        echo "Erreur: Échec installation GRUB BIOS"
        exit 1
    }
fi

grub-mkconfig -o /boot/grub/grub.cfg || {
    echo "Erreur: Échec génération config GRUB"
    exit 1
}

# Installation des outils supplémentaires
pacman -S --noconfirm iw wpa_supplicant dialog git reflector lshw unzip htop
pacman -S --noconfirm wget pulseaudio alsa-utils alsa-plugins pavucontrol xdg-user-dirs

CHROOT_SCRIPT
    
    chmod +x /mnt/root/chroot_config.sh
    arch-chroot /mnt /root/chroot_config.sh || error_exit "Échec configuration système"
    
    log "Configuration système terminée"
}


# Fonction principale
main() {
    log "=== DEBUT DE L'INSTALLATION ARCH LINUX (UEFI/BIOS) ==="
    log "Fichier de log: $LOG_FILE"

    # Étapes préparatoires
    check_prerequisites          # Vérification internet, disque, etc.
    partition_menu              # Affichage du menu et gestion du choix utilisateur
    prepare_disk_for_format     # Préparation du disque pour formatage
    format_partitions           # Formatage des partitions
    mount_partitions            # Montage des partitions
    
    # Installation et configuration
    install_base                # Installation du système de base
    configure_system            # Configuration des paramètres système (corrigée)
    
    # SÉPARATION : Configuration des mots de passe manuellement
    setup_root_password         # Configuration manuelle mot de passe root
    
    install_gui                 # Installation de l'environnement graphique
    setup_user                  # Création du compte utilisateur (corrigée)
    
    # SÉPARATION : Configuration mot de passe utilisateur manuellement  
    setup_user_password         # Configuration manuelle mot de passe utilisateur
    
    create_post_install_script  # Création du script post-installation

    # Message final et nettoyage
    log "=== INSTALLATION TERMINEE ==="
    echo ""
    echo "=============================================================="
    echo "                  INSTALLATION TERMINEE                      "
    echo "=============================================================="
    echo "  Mode de boot: $BOOT_MODE"
    echo "  Utilisateur créé: $USERNAME"
    echo "  Hostname: $HOSTNAME"
    echo "  1. Redémarrez le système: reboot                           "
    echo "  2. Connectez-vous avec l'utilisateur: $USERNAME           "
    echo "  3. Exécutez le script post-installation:                   "
    echo "     ./post_install.sh                                       "
    echo "                                                              "
    echo "  Log sauvegardé dans: /root/arch_install.log                 "
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
