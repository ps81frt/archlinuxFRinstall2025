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
DISK="/dev/sda"
USERNAME="cyber"
HOSTNAME="cyber"
BOOT_MODE=""

# Fonction de gestion d'erreur
error_exit() {
    echo "ERROR: $1"
    exit 1
}

# Fonction de vérification des prérequis
check_prerequisites() {
    # Vérification connexion internet
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_exit "Pas de connexion internet détectée"
    fi

    # Détection du mode de boot (UEFI ou BIOS)
    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi

    # Vérification existence du disque
    if [[ ! -b "$DISK" ]]; then
        error_exit "Disque $DISK non trouvé"
    fi

    # Configuration clavier français
    loadkeys fr
}

# Fonction de partitionnement automatique avec détection de taille
auto_partition() {
    local disk=$1

    # Détection de la taille du disque en GB
    local disk_size=$(lsblk -b -d -n -o SIZE "$disk" | head -1)
    local disk_size_gb=$((disk_size / 1024 / 1024 / 1024))

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
    elif [[ $disk_size_gb -le 256 ]]; then
        swap_size="4G"
        root_size="50G"
        home_size="$((disk_size_gb - 80))G"
    elif [[ $disk_size_gb -le 512 ]]; then
        swap_size="8G"
        root_size="60G"
        home_size="200G"
    else
        swap_size="16G"
        root_size="80G"
        home_size="300G"
    fi

    echo ""
    echo "ATTENTION: Cela va effacer toutes les données du disque $disk!"
    read -p "Voulez-vous continuer avec cette configuration? [y/N]: " confirm

    if [[ $confirm != [yY] ]]; then
        echo "Partitionnement annulé par l'utilisateur"
        exit 0
    fi

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

    # Nettoyage du disque
    sgdisk --zap-all "$disk" || error_exit "Échec du nettoyage du disque"

    if [[ $has_separate_home == false ]]; then
        sgdisk --clear \
               --new=1:0:+$boot_size --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$swap_size --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$root_size --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:0 --typecode=4:8300 --change-name=4:'Linux data' \
               "$disk" || error_exit "Échec de la création des partitions"
    else
        sgdisk --clear \
               --new=1:0:+$boot_size --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$swap_size --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$root_size --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:+$home_size --typecode=4:8302 --change-name=4:'Linux home' \
               --new=5:0:0 --typecode=5:8300 --change-name=5:'Linux data' \
               "$disk" || error_exit "Échec de la création des partitions"
    fi

    sleep 2
    partprobe "$disk"
    sleep 2
}

# Partitionnement BIOS (MBR)
partition_bios() {
    local disk=$1 boot_size=$2 swap_size=$3 root_size=$4 home_size=$5 has_separate_home=$6

    # Nettoyage du disque
    dd if=/dev/zero of="$disk" bs=512 count=1 2>/dev/null || true

    if [[ $has_separate_home == false ]]; then
        fdisk "$disk" << EOF
n
p
1

+${boot_size}
t
1
n
p
2

+${swap_size}
t
2
82
n
p
3

+${root_size}
w
EOF
    else
        fdisk "$disk" << EOF
n
p
1

+${boot_size}
t
1
n
p
2

+${swap_size}
t
2
82
n
p
3

+${root_size}
n
p
4

w
EOF
    fi

    sleep 2
    partprobe "$disk"
    sleep 2
}

# Ici vos autres fonctions : partition_menu, format_partitions, mount_partitions, install_base, configure_system, install_gui, setup_user, create_post_install_script, cleanup
# (Les définitions exactes n’étaient pas dans le pastebin, donc on suppose qu’elles sont présentes et inchangées)

# Fonction principale
main() {
    echo "=== DEBUT DE L'INSTALLATION ARCH LINUX (UEFI/BIOS) ==="

    check_prerequisites
    partition_menu
    format_partitions
    mount_partitions
    install_base
    configure_system
    install_gui
    setup_user
    create_post_install_script

    echo "=== INSTALLATION TERMINEE ==="
    echo ""
    echo "=============================================================="
    echo "                  INSTALLATION TERMINEE                      "
    echo "=============================================================="
    echo "  Mode de boot: $BOOT_MODE"
    echo "  1. Redémarrez le système: reboot                           "
    echo "  2. Connectez-vous avec l'utilisateur: $USERNAME           "
    echo "  3. Exécutez le script post-installation:                   "
    echo "     ./post_install.sh                                       "
    echo ""
    echo "  N'oubliez pas de donner une étoile sur GitHub !           "
    echo "=============================================================="
    echo ""

    read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_confirm
    if [[ $reboot_confirm == [yY] ]]; then
        cleanup
        reboot
    else
        cleanup
        echo "Redémarrage annulé. N'oubliez pas de redémarrer manuellement."
    fi
}

# Point d'entrée du script
if [[ $ZSH_EVAL_CONTEXT == *:file ]]; then
    main "$@"
fi
