#!/bin/bash

# Configuration initiale
loadkeys fr
localectl list-keymaps
ls /sys/firmware/efi/efivars
ping 8.8.8.8
ping 9.9.9.9
lsblk

# Disque 250 Go - Configuration des partitions
# /dev/sda1 boot partition (1G)
# /dev/sda2 swap partition (4G)
# /dev/sda3 root partition (50G)
# /dev/sda4 home partition (100G)
# /dev/sda5 data partition (remaining disk space ~95G)

# Fonction de partitionnement automatique avec détection de taille
auto_partition() {
    local DISK=$1
    
    # Détection de la taille du disque en GB
    local DISK_SIZE=$(lsblk -b -d -n -o SIZE $DISK | head -1)
    local DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024 / 1024))
    
    echo "=== DÉTECTION DU DISQUE ==="
    echo "Disque: $DISK"
    echo "Taille détectée: ${DISK_SIZE_GB} GB"
    echo ""
    
    # Calcul automatique des tailles selon le disque
    local EFI_SIZE="1G"
    local SWAP_SIZE
    local ROOT_SIZE
    local HOME_SIZE
    
    if [[ $DISK_SIZE_GB -lt 64 ]]; then
        echo "ERREUR: Disque trop petit (minimum 64 GB requis)"
        exit 1
    elif [[ $DISK_SIZE_GB -le 128 ]]; then
        # Disque <= 128 GB
        SWAP_SIZE="2G"
        ROOT_SIZE="30G"
        HOME_SIZE="0"  # Pas de partition home séparée
        echo "Configuration pour petit disque (≤128 GB):"
        echo "  EFI: $EFI_SIZE"
        echo "  SWAP: $SWAP_SIZE" 
        echo "  ROOT: $ROOT_SIZE (avec /home intégré)"
        echo "  DATA: Reste du disque (~$((DISK_SIZE_GB - 33)) GB)"
    elif [[ $DISK_SIZE_GB -le 256 ]]; then
        # Disque <= 256 GB
        SWAP_SIZE="4G"
        ROOT_SIZE="50G"
        HOME_SIZE="$((DISK_SIZE_GB - 80))G"
        echo "Configuration pour disque moyen (≤256 GB):"
        echo "  EFI: $EFI_SIZE"
        echo "  SWAP: $SWAP_SIZE"
        echo "  ROOT: $ROOT_SIZE"
        echo "  HOME: $HOME_SIZE"
        echo "  DATA: Reste du disque (~25 GB)"
    elif [[ $DISK_SIZE_GB -le 512 ]]; then
        # Disque <= 512 GB
        SWAP_SIZE="8G"
        ROOT_SIZE="60G"
        HOME_SIZE="200G"
        echo "Configuration pour disque moyen-grand (≤512 GB):"
        echo "  EFI: $EFI_SIZE"
        echo "  SWAP: $SWAP_SIZE"
        echo "  ROOT: $ROOT_SIZE"
        echo "  HOME: $HOME_SIZE"
        echo "  DATA: Reste du disque (~$((DISK_SIZE_GB - 269)) GB)"
    else
        # Disque > 512 GB
        SWAP_SIZE="16G"
        ROOT_SIZE="80G"
        HOME_SIZE="300G"
        echo "Configuration pour grand disque (>512 GB):"
        echo "  EFI: $EFI_SIZE"
        echo "  SWAP: $SWAP_SIZE"
        echo "  ROOT: $ROOT_SIZE"
        echo "  HOME: $HOME_SIZE"
        echo "  DATA: Reste du disque (~$((DISK_SIZE_GB - 397)) GB)"
    fi
    
    echo ""
    echo "ATTENTION: Cela va effacer toutes les données du disque!"
    read -p "Voulez-vous continuer avec cette configuration? [y/N]: " confirm
    
    if [[ $confirm != [yY] ]]; then
        echo "Partitionnement annulé."
        exit 1
    fi
    
    # Création automatique des partitions avec sgdisk
    sgdisk --zap-all $DISK
    
    if [[ $HOME_SIZE == "0" ]]; then
        # Configuration sans partition home séparée (petits disques)
        sgdisk --clear \
               --new=1:0:+$EFI_SIZE --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$SWAP_SIZE --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$ROOT_SIZE --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:0 --typecode=4:8300 --change-name=4:'Linux data' \
               $DISK
    else
        # Configuration complète avec partition home
        sgdisk --clear \
               --new=1:0:+$EFI_SIZE --typecode=1:ef00 --change-name=1:'EFI System' \
               --new=2:0:+$SWAP_SIZE --typecode=2:8200 --change-name=2:'Linux swap' \
               --new=3:0:+$ROOT_SIZE --typecode=3:8304 --change-name=3:'Linux root' \
               --new=4:0:+$HOME_SIZE --typecode=4:8302 --change-name=4:'Linux home' \
               --new=5:0:0 --typecode=5:8300 --change-name=5:'Linux data' \
               $DISK
    fi
    
    # Vérification du partitionnement
    echo "Partitionnement terminé. Vérification:"
    sgdisk --print $DISK
    lsblk $DISK
}

# Fonction de partitionnement manuel
manual_partition() {
    local DISK=$1
    
    echo "Partitionnement manuel de $DISK avec gdisk"
    echo "Suivez ces étapes dans gdisk:"
    echo ""
    echo "1. Nettoyage de la table de partition:"
    echo "   Command: o"
    echo "   Confirm: Y"
    echo ""
    echo "2. EFI partition (boot) - 1G:"
    echo "   Command: n"
    echo "   Partition number: ENTER (1)"
    echo "   First sector: ENTER"
    echo "   Last sector: +1G"
    echo "   Hex code: EF00"
    echo ""
    echo "3. SWAP partition - 4G:"
    echo "   Command: n"
    echo "   Partition number: ENTER (2)"
    echo "   First sector: ENTER"
    echo "   Last sector: +4G"
    echo "   Hex code: 8200"
    echo ""
    echo "4. Root partition (/) - 50G:"
    echo "   Command: n"
    echo "   Partition number: ENTER (3)"
    echo "   First sector: ENTER"
    echo "   Last sector: +50G"
    echo "   Hex code: 8304"
    echo ""
    echo "5. Home partition - 100G:"
    echo "   Command: n"
    echo "   Partition number: ENTER (4)"
    echo "   First sector: ENTER"
    echo "   Last sector: +100G"
    echo "   Hex code: 8302"
    echo ""
    echo "6. Data partition - reste du disque:"
    echo "   Command: n"
    echo "   Partition number: ENTER (5)"
    echo "   First sector: ENTER"
    echo "   Last sector: ENTER"
    echo "   Hex code: ENTER (8300)"
    echo ""
    echo "7. Sauvegarde et quitte:"
    echo "   Command: w"
    echo "   Confirm: Y"
    echo ""
    read -p "Appuyez sur Entrée pour lancer gdisk..."
    gdisk $DISK
}

# Menu de choix du partitionnement
echo "=== CHOIX DU PARTITIONNEMENT ==="
echo "1) Partitionnement automatique (recommandé)"
echo "2) Partitionnement manuel avec gdisk"
echo "3) Passer (partitions déjà créées)"
echo ""
read -p "Votre choix [1-3]: " choice

case $choice in
    1)
        echo "Partitionnement automatique sélectionné"
        auto_partition /dev/sda
        ;;
    2)
        echo "Partitionnement manuel sélectionné"
        manual_partition /dev/sda
        ;;
    3)
        echo "Partitionnement ignoré"
        ;;
    *)
        echo "Choix invalide, partitionnement automatique par défaut"
        auto_partition /dev/sda
        ;;
esac

# Formatage des partitions
mkfs.fat -F32 /dev/sda1
mkswap /dev/sda2
mkfs.ext4 /dev/sda3
mkfs.ext4 /dev/sda4
mkfs.ext4 /dev/sda5

# Adaptation du montage selon la configuration
mount_partitions() {
    local DISK=$1
    local DISK_SIZE_GB=$(lsblk -b -d -n -o SIZE $DISK | head -1)
    DISK_SIZE_GB=$((DISK_SIZE_GB / 1024 / 1024 / 1024))
    
    # Montage de base
    swapon ${DISK}2
    mount ${DISK}3 /mnt
    
    if [[ $DISK_SIZE_GB -le 128 ]]; then
        # Configuration petit disque (pas de partition home séparée)
        mkdir /mnt/{boot,data}
        mount ${DISK}1 /mnt/boot
        mount ${DISK}4 /mnt/data
        echo "Configuration petit disque: /home intégré dans /"
    else
        # Configuration normale avec partition home séparée
        mkdir /mnt/{boot,home,data}
        mount ${DISK}1 /mnt/boot
        mount ${DISK}4 /mnt/home
        mount ${DISK}5 /mnt/data
        echo "Configuration normale: partition /home séparée"
    fi
}

# Montage automatique des partitions
mount_partitions /dev/sda

# Installation de base
timedatectl set-ntp true
pacstrap /mnt base base-devel openssh linux linux-firmware vim
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration dans chroot
arch-chroot /mnt

# Configuration locale
vim /etc/locale.gen
# Décommenter : fr_FR.UTF-8 UTF-8
locale-gen

vim /etc/locale.conf
# Contenu :
# LANG=fr_FR.UTF-8
# LANGUAGE=fr_FR
# LC_ALL=C

vim /etc/vconsole.conf
# Contenu :
# KEYMAP=fr

# Configuration timezone France
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# Installation des services réseau
pacman -S dhcpcd networkmanager network-manager-applet
systemctl enable sshd
systemctl enable dhcpcd
systemctl enable NetworkManager

# Installation et configuration GRUB EFI
pacman -S grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Configuration hostname
echo cyber > /etc/hostname

# Configuration /etc/hosts
vim /etc/hosts
# Contenu :
# 127.0.0.1	localhost.localdomain	localhost
# ::1		localhost.localdomain	localhost
# 127.0.0.1	cyber.localdomain	cyber

# Installation des outils supplémentaires
pacman -S iw wpa_supplicant dialog intel-ucode git reflector lshw unzip htop
pacman -S wget pulseaudio alsa-utils alsa-plugins pavucontrol xdg-user-dirs

# Configuration mot de passe root
passwd

# Sortie du chroot
exit

# Démontage et redémarrage
umount -R /mnt
swapoff /dev/sda2
reboot

#--------------------------------------------------------------------------
# APRÈS REDÉMARRAGE - Configuration utilisateur
#--------------------------------------------------------------------------

# Création utilisateur
useradd -m -g users -G wheel,storage,power,audio cyber
passwd cyber

# Configuration sudo
EDITOR=vim visudo
# Décommenter : %wheel ALL=(ALL) ALL
# Optionnel pour sudo sans mot de passe : %wheel ALL=(ALL) NOPASSWD: ALL

# Connexion utilisateur
su - cyber

# Configuration utilisateur
xdg-user-dirs-update
mkdir Sources
cd Sources

# Installation AUR helper
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

# Configuration pacman
sudo vim /etc/pacman.conf
# Décommenter Color et autres options si nécessaire

# Installation audio et bluetooth
yay -S pa-applet-git
sudo pacman -S bluez bluez-utils blueman
sudo systemctl enable bluetooth

# Gestion de l'alimentation
sudo pacman -S tlp tlp-rdw powertop acpi
sudo systemctl enable tlp
sudo systemctl enable tlp-sleep
sudo systemctl mask systemd-rfkill.service
sudo systemctl mask systemd-rfkill.socket
sudo pacman -S acpi_call

# Optimisation SSD
sudo systemctl enable fstrim.timer

# Installation environnement graphique
sudo pacman -S xorg-server xorg-apps xorg-xinit
sudo pacman -S i3-gaps i3blocks i3lock numlockx
sudo pacman -S lightdm lightdm-gtk-greeter
sudo systemctl enable lightdm

# Installation polices
sudo pacman -S noto-fonts ttf-ubuntu-font-family ttf-dejavu ttf-freefont
sudo pacman -S ttf-liberation ttf-droid ttf-roboto terminus-font

# Applications de base
sudo pacman -S rxvt-unicode ranger rofi dmenu
sudo pacman -S firefox vlc

# Premier redémarrage graphique
sudo reboot

# Après redémarrage - configuration finale
sudo pacman -S zsh
sudo pacman -S lxappearance
sudo pacman -S arc-gtk-theme
sudo pacman -S papirus-icon-theme

# Configuration thème lightdm
sudo vim /etc/lightdm/lightdm-gtk-greeter.conf
# Contenu :
# [greeter]
# theme-name = Arc-Dark
# icon-theme-name = Papirus-Dark
# background = #2f343f