#!/bin/bash

# Script de partitionnement GPT UEFI customisable pour Arch Linux
# Permet de personnaliser toutes les tailles de partitions

set -e  # Arrêter le script en cas d'erreur

echo "=== Script de partitionnement GPT UEFI customisable pour Arch Linux ==="
echo ""

# Fonction pour valider les entrées numériques
validate_number() {
    local input=$1
    local min=${2:-1}
    local max=${3:-1000}
    
    if [[ ! $input =~ ^[0-9]+$ ]] || [ $input -lt $min ] || [ $input -gt $max ]; then
        return 1
    fi
    return 0
}

# Fonction pour afficher la taille disponible
show_disk_info() {
    local disk=$1
    if [[ -b $disk ]]; then
        local size_bytes=$(lsblk -b -d -o SIZE -n $disk 2>/dev/null || echo "0")
        local size_gb=$((size_bytes / 1024 / 1024 / 1024))
        echo "Taille du disque: ${size_gb}Go"
    fi
}

# Configuration du disque
echo "1. Configuration du disque cible"
echo "Disques disponibles:"
lsblk -d -o NAME,SIZE,MODEL | grep -E '^(sd|nvme|vd)'

while true; do
    read -p "Entrez le chemin du disque (ex: /dev/sda): " DISK
    if [[ -b $DISK ]]; then
        show_disk_info $DISK
        read -p "Confirmer ce disque? (oui/non): " confirm
        if [[ $confirm == "oui" ]]; then
            break
        fi
    else
        echo "Erreur: Le disque $DISK n'existe pas!"
    fi
done

# Calcul de l'espace total disponible
TOTAL_SIZE_BYTES=$(lsblk -b -d -o SIZE -n $DISK)
TOTAL_SIZE_GB=$((TOTAL_SIZE_BYTES / 1024 / 1024 / 1024))
echo "Espace total disponible: ${TOTAL_SIZE_GB}Go"
echo ""

# Configuration des partitions
echo "2. Configuration des partitions"
echo "Laissez vide pour utiliser la valeur par défaut entre []"
echo ""

# Partition EFI
while true; do
    read -p "Taille partition EFI en Go [1]: " EFI_SIZE
    EFI_SIZE=${EFI_SIZE:-1}
    if validate_number $EFI_SIZE 1 5; then
        break
    else
        echo "Erreur: Taille EFI doit être entre 1 et 5 Go"
    fi
done

# Partition SWAP
while true; do
    read -p "Taille partition SWAP en Go [4]: " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-4}
    if validate_number $SWAP_SIZE 1 32; then
        break
    else
        echo "Erreur: Taille SWAP doit être entre 1 et 32 Go"
    fi
done

# Partition ROOT
while true; do
    read -p "Taille partition ROOT en Go [50]: " ROOT_SIZE
    ROOT_SIZE=${ROOT_SIZE:-50}
    if validate_number $ROOT_SIZE 10 $((TOTAL_SIZE_GB - 10)); then
        break
    else
        echo "Erreur: Taille ROOT doit être entre 10 et $((TOTAL_SIZE_GB - 10)) Go"
    fi
done

# Partition HOME
USED_SPACE=$((EFI_SIZE + SWAP_SIZE + ROOT_SIZE + 5)) # +5 Go de marge
REMAINING_SPACE=$((TOTAL_SIZE_GB - USED_SPACE))

while true; do
    read -p "Taille partition HOME en Go [100] (Espace restant: ${REMAINING_SPACE}Go): " HOME_SIZE
    HOME_SIZE=${HOME_SIZE:-100}
    if validate_number $HOME_SIZE 10 $REMAINING_SPACE; then
        break
    else
        echo "Erreur: Taille HOME doit être entre 10 et ${REMAINING_SPACE} Go"
    fi
done

# Partition supplémentaire optionnelle
USED_SPACE=$((EFI_SIZE + SWAP_SIZE + ROOT_SIZE + HOME_SIZE + 2))
FINAL_REMAINING=$((TOTAL_SIZE_GB - USED_SPACE))

CREATE_EXTRA="non"
EXTRA_SIZE=0
if [ $FINAL_REMAINING -gt 5 ]; then
    echo "Espace restant: ${FINAL_REMAINING}Go"
    read -p "Créer une partition supplémentaire avec l'espace restant? (oui/non) [oui]: " CREATE_EXTRA
    CREATE_EXTRA=${CREATE_EXTRA:-oui}
    
    if [[ $CREATE_EXTRA == "oui" ]]; then
        EXTRA_SIZE=$FINAL_REMAINING
    fi
fi

# Configuration des systèmes de fichiers
echo ""
echo "3. Configuration des systèmes de fichiers"
echo ""
echo "Systèmes de fichiers disponibles:"
echo "  1) ext4     - Système de fichiers Linux standard (recommandé)"
echo "  2) ext3     - Version précédente d'ext4"
echo "  3) ext2     - Système de fichiers Linux basique"
echo "  4) btrfs    - Système de fichiers moderne avec snapshots"
echo "  5) xfs      - Système de fichiers haute performance"
echo "  6) f2fs     - Optimisé pour stockage flash/SSD"
echo "  7) nilfs2   - Système de fichiers log-structuré"
echo "  8) reiserfs - Système de fichiers pour petits fichiers"
echo "  9) jfs      - Système de fichiers IBM"
echo " 10) ntfs     - Compatible Windows (lecture/écriture)"
echo " 11) exfat    - Compatible multi-plateformes"
echo ""

# Fonction pour choisir le système de fichiers
choose_filesystem() {
    local partition_name=$1
    local default_choice=${2:-1}
    
    while true; do
        read -p "Choisissez le système de fichiers pour $partition_name [1-11, défaut: $default_choice]: " choice
        choice=${choice:-$default_choice}
        
        case $choice in
            1) echo "ext4"; return ;;
            2) echo "ext3"; return ;;
            3) echo "ext2"; return ;;
            4) echo "btrfs"; return ;;
            5) echo "xfs"; return ;;
            6) echo "f2fs"; return ;;
            7) echo "nilfs2"; return ;;
            8) echo "reiserfs"; return ;;
            9) echo "jfs"; return ;;
            10) echo "ntfs"; return ;;
            11) echo "exfat"; return ;;
            *) echo "Erreur: Choix invalide. Choisissez entre 1 et 11." ;;
        esac
    done
}

# Système de fichiers ROOT
ROOT_FS=$(choose_filesystem "ROOT" 1)
echo "Système de fichiers ROOT: $ROOT_FS"

# Système de fichiers HOME
HOME_FS=$(choose_filesystem "HOME" 1)
echo "Système de fichiers HOME: $HOME_FS"

# Système de fichiers partition supplémentaire
EXTRA_FS="ext4"
if [[ $CREATE_EXTRA == "oui" ]]; then
    EXTRA_FS=$(choose_filesystem "partition supplémentaire" 1)
    echo "Système de fichiers partition supplémentaire: $EXTRA_FS"
fi

# Labels des partitions
echo ""
echo "4. Configuration des labels (optionnel)"
read -p "Label partition EFI [EFI]: " EFI_LABEL
EFI_LABEL=${EFI_LABEL:-EFI}

read -p "Label partition SWAP [SWAP]: " SWAP_LABEL
SWAP_LABEL=${SWAP_LABEL:-SWAP}

read -p "Label partition ROOT [ROOT]: " ROOT_LABEL
ROOT_LABEL=${ROOT_LABEL:-ROOT}

read -p "Label partition HOME [HOME]: " HOME_LABEL
HOME_LABEL=${HOME_LABEL:-HOME}

EXTRA_LABEL="DATA"
if [[ $CREATE_EXTRA == "oui" ]]; then
    read -p "Label partition supplémentaire [DATA]: " EXTRA_LABEL
    EXTRA_LABEL=${EXTRA_LABEL:-DATA}
fi

# Résumé de la configuration
echo ""
echo "=== RÉSUMÉ DE LA CONFIGURATION ==="
echo "Disque cible: $DISK (${TOTAL_SIZE_GB}Go)"
echo "Partitions:"
echo "  ${DISK}1: ${EFI_SIZE}Go   - EFI System (FAT32) - $EFI_LABEL"
echo "  ${DISK}2: ${SWAP_SIZE}Go   - Linux Swap - $SWAP_LABEL"
echo "  ${DISK}3: ${ROOT_SIZE}Go  - Linux Root ($ROOT_FS) - $ROOT_LABEL"
echo "  ${DISK}4: ${HOME_SIZE}Go - Linux Home ($HOME_FS) - $HOME_LABEL"
if [[ $CREATE_EXTRA == "oui" ]]; then
    echo "  ${DISK}5: ${EXTRA_SIZE}Go - Partition supplémentaire ($EXTRA_FS) - $EXTRA_LABEL"
fi
echo ""

echo "ATTENTION: Ce script va EFFACER TOUTES LES DONNÉES du disque $DISK"
read -p "Confirmer et procéder au partitionnement? (CONFIRMER/annuler): " final_confirm
if [[ $final_confirm != "CONFIRMER" ]]; then
    echo "Opération annulée."
    exit 1
fi

# Vérifier que sgdisk est installé
if ! command -v sgdisk &> /dev/null; then
    echo "Erreur: sgdisk n'est pas installé. Installez gptfdisk:"
    echo "sudo pacman -S gptfdisk"
    exit 1
fi

echo ""
echo "=== DÉBUT DU PARTITIONNEMENT ==="

echo "Démontage des partitions existantes..."
umount ${DISK}* 2>/dev/null || true

echo "Effacement de la table de partition existante..."
sgdisk --zap-all $DISK

echo "Création de la nouvelle table de partition GPT..."

# Créer les partitions
echo "Création de ${DISK}1 (EFI System Partition - ${EFI_SIZE}Go)..."
sgdisk --new=1:0:+${EFI_SIZE}G --typecode=1:ef00 --change-name=1:"$EFI_LABEL" $DISK

echo "Création de ${DISK}2 (Linux Swap - ${SWAP_SIZE}Go)..."
sgdisk --new=2:0:+${SWAP_SIZE}G --typecode=2:8200 --change-name=2:"$SWAP_LABEL" $DISK

echo "Création de ${DISK}3 (Linux Root - ${ROOT_SIZE}Go)..."
sgdisk --new=3:0:+${ROOT_SIZE}G --typecode=3:8300 --change-name=3:"$ROOT_LABEL" $DISK

echo "Création de ${DISK}4 (Linux Home - ${HOME_SIZE}Go)..."
if [[ $CREATE_EXTRA == "oui" ]]; then
    sgdisk --new=4:0:+${HOME_SIZE}G --typecode=4:8300 --change-name=4:"$HOME_LABEL" $DISK
    echo "Création de ${DISK}5 (Partition supplémentaire - ${EXTRA_SIZE}Go)..."
    sgdisk --new=5:0:0 --typecode=5:8300 --change-name=5:"$EXTRA_LABEL" $DISK
else
    sgdisk --new=4:0:0 --typecode=4:8300 --change-name=4:"$HOME_LABEL" $DISK
fi

echo "Vérification de la table de partition..."
sgdisk --print $DISK

echo ""
echo "=== FORMATAGE DES PARTITIONS ==="

echo "Formatage de ${DISK}1 en FAT32 (EFI)..."
mkfs.fat -F32 -n "$EFI_LABEL" ${DISK}1

echo "Création du swap sur ${DISK}2..."
mkswap -L "$SWAP_LABEL" ${DISK}2

echo "Formatage de ${DISK}3 en $ROOT_FS (Root)..."
case $ROOT_FS in
    ext4)
        mkfs.ext4 -L "$ROOT_LABEL" ${DISK}3
        ;;
    ext3)
        mkfs.ext3 -L "$ROOT_LABEL" ${DISK}3
        ;;
    ext2)
        mkfs.ext2 -L "$ROOT_LABEL" ${DISK}3
        ;;
    btrfs)
        mkfs.btrfs -f -L "$ROOT_LABEL" ${DISK}3
        ;;
    xfs)
        mkfs.xfs -f -L "$ROOT_LABEL" ${DISK}3
        ;;
    f2fs)
        mkfs.f2fs -f -l "$ROOT_LABEL" ${DISK}3
        ;;
    nilfs2)
        mkfs.nilfs2 -L "$ROOT_LABEL" ${DISK}3
        ;;
    reiserfs)
        mkfs.reiserfs -l "$ROOT_LABEL" ${DISK}3 << EOF
y
EOF
        ;;
    jfs)
        mkfs.jfs -L "$ROOT_LABEL" ${DISK}3 << EOF
y
EOF
        ;;
    ntfs)
        mkfs.ntfs -f -L "$ROOT_LABEL" ${DISK}3
        ;;
    exfat)
        mkfs.exfat -n "$ROOT_LABEL" ${DISK}3
        ;;
esac

echo "Formatage de ${DISK}4 en $HOME_FS (Home)..."
case $HOME_FS in
    ext4)
        mkfs.ext4 -L "$HOME_LABEL" ${DISK}4
        ;;
    ext3)
        mkfs.ext3 -L "$HOME_LABEL" ${DISK}4
        ;;
    ext2)
        mkfs.ext2 -L "$HOME_LABEL" ${DISK}4
        ;;
    btrfs)
        mkfs.btrfs -f -L "$HOME_LABEL" ${DISK}4
        ;;
    xfs)
        mkfs.xfs -f -L "$HOME_LABEL" ${DISK}4
        ;;
    f2fs)
        mkfs.f2fs -f -l "$HOME_LABEL" ${DISK}4
        ;;
    nilfs2)
        mkfs.nilfs2 -L "$HOME_LABEL" ${DISK}4
        ;;
    reiserfs)
        mkfs.reiserfs -l "$HOME_LABEL" ${DISK}4 << EOF
y
EOF
        ;;
    jfs)
        mkfs.jfs -L "$HOME_LABEL" ${DISK}4 << EOF
y
EOF
        ;;
    ntfs)
        mkfs.ntfs -f -L "$HOME_LABEL" ${DISK}4
        ;;
    exfat)
        mkfs.exfat -n "$HOME_LABEL" ${DISK}4
        ;;
esac

if [[ $CREATE_EXTRA == "oui" ]]; then
    echo "Formatage de ${DISK}5 en $EXTRA_FS (Partition supplémentaire)..."
    case $EXTRA_FS in
        ext4)
            mkfs.ext4 -L "$EXTRA_LABEL" ${DISK}5
            ;;
        ext3)
            mkfs.ext3 -L "$EXTRA_LABEL" ${DISK}5
            ;;
        ext2)
            mkfs.ext2 -L "$EXTRA_LABEL" ${DISK}5
            ;;
        btrfs)
            mkfs.btrfs -f -L "$EXTRA_LABEL" ${DISK}5
            ;;
        xfs)
            mkfs.xfs -f -L "$EXTRA_LABEL" ${DISK}5
            ;;
        f2fs)
            mkfs.f2fs -f -l "$EXTRA_LABEL" ${DISK}5
            ;;
        nilfs2)
            mkfs.nilfs2 -L "$EXTRA_LABEL" ${DISK}5
            ;;
        reiserfs)
            mkfs.reiserfs -l "$EXTRA_LABEL" ${DISK}5 << EOF
y
EOF
            ;;
        jfs)
            mkfs.jfs -L "$EXTRA_LABEL" ${DISK}5 << EOF
y
EOF
            ;;
        ntfs)
            mkfs.ntfs -f -L "$EXTRA_LABEL" ${DISK}5
            ;;
        exfat)
            mkfs.exfat -n "$EXTRA_LABEL" ${DISK}5
            ;;
    esac
fi

echo ""
echo "=== PARTITIONNEMENT TERMINÉ ==="
echo "Table de partition finale:"
lsblk $DISK

echo ""
echo "=== COMMANDES DE MONTAGE POUR L'INSTALLATION ==="
echo "mount ${DISK}3 /mnt"
if [[ $CREATE_EXTRA == "oui" ]]; then
    echo "mkdir -p /mnt/{boot,home,${EXTRA_LABEL,,}}"
    echo "mount ${DISK}1 /mnt/boot"
    echo "mount ${DISK}4 /mnt/home" 
    echo "mount ${DISK}5 /mnt/${EXTRA_LABEL,,}"
else
    echo "mkdir -p /mnt/{boot,home}"
    echo "mount ${DISK}1 /mnt/boot"
    echo "mount ${DISK}4 /mnt/home"
fi
echo "swapon ${DISK}2"

echo ""
echo "Script terminé avec succès!"