#!/usr/bin/bash

# =============================================================================
# INSTALLATION ARCH LINUX SIMPLIFIEE AVEC AUTO-REPRISE - COMPATIBLE UEFI/BIOS
# =============================================================================
# Version: 2025.1-retry
# Base sur: https://github.com/ps81frt/archlinuxfr
# Ameliore avec: Mecanismes de reprise et recuperation d'erreurs
# =============================================================================

set +e  # Ne pas quitter sur les erreurs - nous les gerons avec les reprises

# Configuration
MAX_TENTATIVES=3
DELAI_REPRISE=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FICHIER_LOG="/tmp/arch_install.log"
FICHIER_ETAT="/tmp/install_state"
DOSSIER_SAUVEGARDE="/tmp/install_backup"
DISQUE="/dev/sda"
NOM_UTILISATEUR="cyber"
NOM_HOTE="cyber"
MODE_DEMARRAGE=""

# Etapes d'installation
ETAPE_PREREQUIS=1
ETAPE_PARTITIONNEMENT=2
ETAPE_FORMATAGE=3
ETAPE_MONTAGE=4
ETAPE_INSTALL_BASE=5
ETAPE_CONFIG_SYSTEME=6
ETAPE_CONFIG_UTILISATEUR=7
ETAPE_NETTOYAGE=8

# Fonctions de journalisation
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$FICHIER_LOG"
}

log_succes() {
    echo "[SUCCES $(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$FICHIER_LOG"
}

log_erreur() {
    echo "[ERREUR $(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$FICHIER_LOG"
}

log_avertissement() {
    echo "[ATTENTION $(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$FICHIER_LOG"
}

# Gestion d'etat
sauvegarder_etat() {
    echo "$1" > "$FICHIER_ETAT"
    log "Etat sauvegarde: Etape $1"
}

obtenir_etat() {
    if [[ -f "$FICHIER_ETAT" ]]; then
        cat "$FICHIER_ETAT"
    else
        echo "0"
    fi
}

# Sauvegarde des fichiers critiques
sauvegarder_fichiers() {
    mkdir -p "$DOSSIER_SAUVEGARDE"
    if [[ -f /etc/fstab ]]; then
        cp /etc/fstab "$DOSSIER_SAUVEGARDE/fstab.backup" 2>/dev/null || true
    fi
    log "Sauvegarde creee dans $DOSSIER_SAUVEGARDE"
}

# Mecanisme de reprise ameliore avec backoff exponentiel
retry_commande() {
    local cmd="$1"
    local max_tentatives="${2:-$MAX_TENTATIVES}"
    local delai="${3:-$DELAI_REPRISE}"
    local tentative=1
    
    while [[ $tentative -le $max_tentatives ]]; do
        log "Tentative $tentative/$max_tentatives: $cmd"
        
        if eval "$cmd"; then
            log_succes "Commande reussie a la tentative $tentative"
            return 0
        else
            local code_sortie=$?
            log_erreur "Commande echouee a la tentative $tentative (code de sortie: $code_sortie)"
            
            if [[ $tentative -lt $max_tentatives ]]; then
                log_avertissement "Nouvelle tentative dans $delai secondes..."
                sleep "$delai"
                delai=$((delai * 2))  # Backoff exponentiel
            fi
        fi
        
        ((tentative++))
    done
    
    log_erreur "Commande echouee apres $max_tentatives tentatives"
    return 1
}

# Verification reseau avec reprise
verifier_reseau() {
    log "Verification de la connectivite reseau..."
    if retry_commande "ping -c 3 -W 5 8.8.8.8" 3 5; then
        log_succes "Connectivite reseau confirmee"
        return 0
    else
        log_erreur "Connectivite reseau echouee"
        return 1
    fi
}

# Detection du mode de demarrage
detecter_mode_demarrage() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        MODE_DEMARRAGE="uefi"
    else
        MODE_DEMARRAGE="bios"
    fi
    log "Mode de demarrage detecte: $MODE_DEMARRAGE"
}

# Verification des prerequis avec reprise
verifier_prerequis() {
    log "=== VERIFICATION DES PREREQUIS ==="
    sauvegarder_etat $ETAPE_PREREQUIS
    
    # Verification reseau
    if ! verifier_reseau; then
        log_erreur "Pas de connexion internet"
        return 1
    fi
    
    # Detection du mode de demarrage
    detecter_mode_demarrage
    
    # Verification du disque
    if [[ ! -b "$DISQUE" ]]; then
        log_erreur "Disque $DISQUE non trouve"
        return 1
    fi
    log_succes "Disque $DISQUE detecte"
    
    # Disposition clavier
    if ! retry_commande "loadkeys fr" 2 3; then
        log_avertissement "Echec du chargement de la disposition clavier francaise"
    fi
    
    log_succes "Verification des prerequis terminee"
    return 0
}

# Partitionnement automatique simplifie
partitionnement_auto() {
    local disque=$1
    log "=== PARTITIONNEMENT AUTOMATIQUE ($MODE_DEMARRAGE) ==="
    sauvegarder_etat $ETAPE_PARTITIONNEMENT
    
    # Obtenir la taille du disque
    local taille_disque=$(lsblk -b -d -n -o SIZE "$disque" | head -1)
    local taille_disque_gb=$((taille_disque / 1024 / 1024 / 1024))
    
    log "Disque: $disque, Taille: ${taille_disque_gb}GB, Mode de demarrage: $MODE_DEMARRAGE"
    
    # Schema de partitionnement simple
    local taille_boot="512M"
    local taille_swap="4G"
    local taille_racine="50G"
    
    if [[ $taille_disque_gb -lt 64 ]]; then
        log_erreur "Disque trop petit (minimum 64GB requis)"
        return 1
    fi
    
    echo "ATTENTION: Ceci effacera toutes les donnees sur $disque!"
    read -p "Continuer? [y/N]: " confirmer
    if [[ $confirmer != [yY] ]]; then
        log "Partitionnement annule"
        return 1
    fi
    
    # Partitionnement avec reprise
    if [[ $MODE_DEMARRAGE == "uefi" ]]; then
        if ! retry_commande "partitionner_uefi $disque $taille_boot $taille_swap $taille_racine" 2 5; then
            log_erreur "Partitionnement UEFI echoue"
            return 1
        fi
    else
        if ! retry_commande "partitionner_bios $disque $taille_boot $taille_swap $taille_racine" 2 5; then
            log_erreur "Partitionnement BIOS echoue"
            return 1
        fi
    fi
    
    log_succes "Partitionnement termine"
    return 0
}

# Partitionnement UEFI
partitionner_uefi() {
    local disque=$1 taille_boot=$2 taille_swap=$3 taille_racine=$4
    
    log "Creation des partitions UEFI/GPT..."
    
    # Nettoyer le disque
    sgdisk --zap-all "$disque" || return 1
    sleep 2
    
    # Creer les partitions
    sgdisk --clear \
           --new=1:0:+$taille_boot --typecode=1:ef00 --change-name=1:'Systeme EFI' \
           --new=2:0:+$taille_swap --typecode=2:8200 --change-name=2:'Swap Linux' \
           --new=3:0:+$taille_racine --typecode=3:8304 --change-name=3:'Racine Linux' \
           --new=4:0:0 --typecode=4:8300 --change-name=4:'Donnees Linux' \
           "$disque" || return 1
    
    sleep 3
    partprobe "$disque"
    sleep 2
    return 0
}

# Partitionnement BIOS
partitionner_bios() {
    local disque=$1 taille_boot=$2 taille_swap=$3 taille_racine=$4
    
    log "Creation des partitions BIOS/MBR..."
    
    # Nettoyer le disque
    wipefs -af "$disque" || return 1
    dd if=/dev/zero of="$disque" bs=512 count=1 2>/dev/null || return 1
    sleep 2
    
    # Creer les partitions avec fdisk
    {
        echo o      # Nouvelle table de partitions DOS
        echo n; echo p; echo 1; echo; echo +$taille_boot  # Partition de demarrage
        echo a; echo 1  # Rendre amorcable
        echo n; echo p; echo 2; echo; echo +$taille_swap  # Partition swap
        echo n; echo p; echo 3; echo; echo +$taille_racine  # Partition racine
        echo n; echo p; echo 4; echo; echo              # Partition donnees (reste)
        echo t; echo 2; echo 82  # Definir le type swap
        echo w      # Ecrire les changements
    } | fdisk "$disque" || return 1
    
    sleep 3
    partprobe "$disque"
    sleep 2
    return 0
}

# Formater les partitions avec reprise
formater_partitions() {
    log "=== FORMATAGE DES PARTITIONS ==="
    sauvegarder_etat $ETAPE_FORMATAGE
    
    sauvegarder_fichiers
    
    # Demonter les montages existants
    for pointmontage in $(lsblk -ln -o NAME,MOUNTPOINT | grep "^$(basename $DISQUE)" | awk '$2!="" {print $2}' | tac); do
        if [[ -n "$pointmontage" ]]; then
            umount "$pointmontage" 2>/dev/null || true
        fi
    done
    
    sleep 2
    
    # Formater avec reprise
    if [[ $MODE_DEMARRAGE == "uefi" ]]; then
        retry_commande "mkfs.fat -F32 ${DISQUE}1" 2 3 || return 1
    else
        retry_commande "mkfs.ext4 -F ${DISQUE}1" 2 3 || return 1
    fi
    
    retry_commande "mkswap ${DISQUE}2" 2 3 || return 1
    retry_commande "mkfs.ext4 -F ${DISQUE}3" 2 3 || return 1
    retry_commande "mkfs.ext4 -F ${DISQUE}4" 2 3 || return 1
    
    log_succes "Formatage termine"
    return 0
}

# Monter les partitions avec reprise
monter_partitions() {
    log "=== MONTAGE DES PARTITIONS ==="
    sauvegarder_etat $ETAPE_MONTAGE
    
    # Monter la racine en premier
    retry_commande "mount ${DISQUE}3 /mnt" 2 3 || return 1
    
    # Activer le swap
    retry_commande "swapon ${DISQUE}2" 2 3 || return 1
    
    # Creer les points de montage et monter
    mkdir -p /mnt/{boot,data}
    retry_commande "mount ${DISQUE}1 /mnt/boot" 2 3 || return 1
    retry_commande "mount ${DISQUE}4 /mnt/data" 2 3 || return 1
    
    log_succes "Montage termine"
    lsblk
    return 0
}

# Installation de base avec reprise
installer_base() {
    log "=== INSTALLATION DE BASE ==="
    sauvegarder_etat $ETAPE_INSTALL_BASE
    
    # Synchronisation de l'heure
    retry_commande "timedatectl set-ntp true" 2 3
    
    # Mise a jour des miroirs
    if ! retry_commande "reflector --country France --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist" 2 5; then
        log_avertissement "Mise a jour des miroirs echouee, continuation avec les miroirs par defaut"
    fi
    
    # Installer les paquets de base avec reprise
    if ! retry_commande "pacstrap /mnt base base-devel linux linux-firmware vim openssh intel-ucode" 3 10; then
        log_erreur "Installation de base echouee"
        return 1
    fi
    
    # Generer fstab
    retry_commande "genfstab -U /mnt >> /mnt/etc/fstab" 2 3 || return 1
    
    log_succes "Installation de base terminee"
    return 0
}

# Configuration du systeme dans chroot
configurer_systeme() {
    log "=== CONFIGURATION DU SYSTEME ==="
    sauvegarder_etat $ETAPE_CONFIG_SYSTEME
    
    # Copier le script et les informations d'etat
    cp "$0" /mnt/root/ 2>/dev/null || true
    echo "$MODE_DEMARRAGE" > /mnt/root/boot_mode
    
    # Configurer dans chroot avec reprise
    if ! retry_commande "arch-chroot /mnt /bin/bash -c '
        # Locale
        echo \"fr_FR.UTF-8 UTF-8\" >> /etc/locale.gen
        locale-gen
        echo \"LANG=fr_FR.UTF-8\" > /etc/locale.conf
        echo \"KEYMAP=fr\" > /etc/vconsole.conf
        
        # Fuseau horaire
        ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
        hwclock --systohc
        
        # Nom d'hote
        echo \"$NOM_HOTE\" > /etc/hostname
        echo \"127.0.0.1 localhost\" > /etc/hosts
        echo \"127.0.0.1 $NOM_HOTE\" >> /etc/hosts
        
        # Reseau
        pacman -S --noconfirm dhcpcd networkmanager
        systemctl enable dhcpcd NetworkManager
        
        # Installation GRUB
        pacman -S --noconfirm grub
        if [[ \$(cat /root/boot_mode) == \"uefi\" ]]; then
            pacman -S --noconfirm efibootmgr
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        else
            grub-install --target=i386-pc $DISQUE
        fi
        grub-mkconfig -o /boot/grub/grub.cfg
        
        # Definir le mot de passe root
        echo \"root:root\" | chpasswd
    '" 3 10; then
        log_erreur "Configuration du systeme echouee"
        return 1
    fi
    
    log_succes "Configuration du systeme terminee"
    return 0
}

# Configuration utilisateur
configurer_utilisateur() {
    log "=== CONFIGURATION UTILISATEUR ==="
    sauvegarder_etat $ETAPE_CONFIG_UTILISATEUR
    
    if ! retry_commande "arch-chroot /mnt /bin/bash -c '
        useradd -m -g users -G wheel,storage,power,audio $NOM_UTILISATEUR
        echo \"$NOM_UTILISATEUR:$NOM_UTILISATEUR\" | chpasswd
        sed -i \"s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/\" /etc/sudoers
    '" 2 5; then
        log_erreur "Configuration utilisateur echouee"
        return 1
    fi
    
    log_succes "Configuration utilisateur terminee"
    return 0
}

# Nettoyage
nettoyage() {
    log "=== NETTOYAGE ==="
    sauvegarder_etat $ETAPE_NETTOYAGE
    
    umount -R /mnt 2>/dev/null || true
    swapoff "${DISQUE}2" 2>/dev/null || true
    rm -f /tmp/install_state
    
    log_succes "Nettoyage termine"
}

# Fonction de recuperation
recuperer_installation() {
    local etape_actuelle=$(obtenir_etat)
    log "=== MODE RECUPERATION - Reprise a partir de l'etape $etape_actuelle ==="
    
    case $etape_actuelle in
        0|$ETAPE_PREREQUIS)
            log "Demarrage a partir de la verification des prerequis"
            return 1  # Besoin de recommencer
            ;;
        $ETAPE_PARTITIONNEMENT)
            log "Reprise a partir du partitionnement"
            if ! verifier_reseau; then return 1; fi
            detecter_mode_demarrage
            return 2  # Reprendre a partir du partitionnement
            ;;
        $ETAPE_FORMATAGE)
            log "Reprise a partir du formatage"
            detecter_mode_demarrage
            return 3  # Reprendre a partir du formatage
            ;;
        $ETAPE_MONTAGE)
            log "Reprise a partir du montage"
            detecter_mode_demarrage
            return 4  # Reprendre a partir du montage
            ;;
        $ETAPE_INSTALL_BASE)
            log "Reprise a partir de l'installation de base"
            return 5  # Reprendre a partir de l'installation de base
            ;;
        $ETAPE_CONFIG_SYSTEME)
            log "Reprise a partir de la configuration du systeme"
            detecter_mode_demarrage
            return 6  # Reprendre a partir de la configuration du systeme
            ;;
        $ETAPE_CONFIG_UTILISATEUR)
            log "Reprise a partir de la configuration utilisateur"
            return 7  # Reprendre a partir de la configuration utilisateur
            ;;
        *)
            log "L'installation semble terminee"
            return 8  # Termine
            ;;
    esac
}

# Fonction d'installation principale avec logique de reprise
executer_installation() {
    local etape_debut=1
    local max_reprises_completes=3
    local compteur_reprises_completes=0
    
    # Verifier la recuperation
    if [[ -f "$FICHIER_ETAT" ]]; then
        recuperer_installation
        etape_debut=$?
        if [[ $etape_debut -eq 8 ]]; then
            log_succes "Installation deja terminee"
            return 0
        fi
    fi
    
    while [[ $compteur_reprises_completes -lt $max_reprises_completes ]]; do
        log "=== TENTATIVE D'INSTALLATION $((compteur_reprises_completes + 1))/$max_reprises_completes ==="
        
        case $etape_debut in
            1) if ! verifier_prerequis; then etape_debut=1; continue; fi ;&
            2) if ! partitionnement_auto "$DISQUE"; then etape_debut=2; continue; fi ;&
            3) if ! formater_partitions; then etape_debut=3; continue; fi ;&
            4) if ! monter_partitions; then etape_debut=4; continue; fi ;&
            5) if ! installer_base; then etape_debut=5; continue; fi ;&
            6) if ! configurer_systeme; then etape_debut=6; continue; fi ;&
            7) if ! configurer_utilisateur; then etape_debut=7; continue; fi ;&
            8) nettoyage ;;
        esac
        
        # Si nous arrivons ici, l'installation a reussi
        log_succes "Installation terminee avec succes"
        return 0
    done
    
    log_erreur "Installation echouee apres $max_reprises_completes tentatives"
    return 1
}

# Fonction principale
main() {
    log "=== INSTALLATION ARCH LINUX SIMPLIFIEE AVEC AUTO-REPRISE ==="
    log "Fichier de log: $FICHIER_LOG"
    
    if executer_installation; then
        echo ""
        echo "=============================================================="
        echo "                INSTALLATION TERMINEE                        "
        echo "=============================================================="
        echo "  Mode de demarrage: $MODE_DEMARRAGE"
        echo "  Nom d'utilisateur: $NOM_UTILISATEUR (mot de passe: $NOM_UTILISATEUR)"
        echo "  Mot de passe root: root"
        echo ""
        read -p "Redemarrer maintenant? [y/N]: " confirmer_redemarrage
        if [[ $confirmer_redemarrage == [yY] ]]; then
            reboot
        fi
    else
        echo ""
        echo "=============================================================="
        echo "                INSTALLATION ECHOUEE                         "
        echo "=============================================================="
        echo "  Verifier le fichier de log: $FICHIER_LOG"
        echo "  Vous pouvez relancer le script pour reprendre a partir de la derniere etape reussie"
        echo "=============================================================="
        exit 1
    fi
}

# Point d'entree
if [[ -n "$ZSH_VERSION" ]]; then
    if [[ $ZSH_EVAL_CONTEXT == *:file ]]; then
        main "$@"
    fi
else
    main "$@"
fi
