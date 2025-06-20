loadkeys fr
localectl list-keymaps
ls /sys/firmware/efi/efivars
ping 8.8.8.8
ping 9.9.9.9
lsblk

# Disque 250 Go

    # /dev/sda1 boot partition (1G).
    # /dev/sda2 swap partition (4G).
    # /dev/sda3 root partition (50G).
    # /dev/sda4 home partition (100G).
    # /dev/sda5 data partition (remaining disk space).

    #  gdisk /dev/sda
    #  
    #  Nettoyage de la table de partition
    #     Command: O
    #     Y
    #  EFI partition (boot)
    #     Command: N
    #     ENTER
    #     ENTER
    #     +1G
    #     EF00
    #  SWAP partition
    #     Command: N
    #     ENTER
    #     ENTER
    #     +4G
    #     8200
    #  Root partition (/)
    #     Command: N
    #     ENTER
    #     ENTER
    #     +50G
    #     8304
    #  Home partition
    #     Command: N
    #     ENTER
    #     ENTER
    #     +100G
    #     8302
    #  Data partition
    #     Command: N
    #     ENTER
    #     ENTER
    #     ENTER
    #     ENTER
    #  Sauvegarde et quitte
    #     Command: W
    #     Y




mkfs.fat -F32 /dev/sda1
mkswap /dev/sda2
mkfs.ext4 /dev/sda3
mkfs.ext4 /dev/sda4
mkfs.ext4 /dev/sda5
swapon /dev/sda2
mount /dev/sda3 /mnt
mkdir /mnt/{boot,home}
mount /dev/sda1 /mnt/boot
mount /dev/sda4 /mnt/home

timedatectl set-ntp true
pacstrap /mnt base base-devel openssh linux linux-firmware vim
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
vim /etc/locale.gen
locale-gen
vim /etc/locale.conf

        LANG=fr_FR.UTF-8
        LANGUAGE=fr_FR
        LC_ALL=C

vim /etc/vconsole.conf
        KEYMAP=us

ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock —-systohc
pacman -S dhcpcd networkmanager network-manager-applet
systemctl enable sshd
systemctl enable dhcpcd
systemctl enable NetworkManager
pacman -S grub-efi-x86_64 efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch
grub-mkconfig -o /boot/grub/grub.cfg

echo cyber > /etc/hostname

   127.0.0.1    localhost.localdomain   localhost
   ::1          localhost.localdomain   localhost
   127.0.0.1    cyber.localdomain    cyber

pacman -S iw wpa_supplicant dialog intel-ucode git reflector lshw unzip htop
pacman -S wget pulseaudio alsa-utils alsa-plugins pavucontrol xdg-user-dirs
passwd
exit
umount -R /mnt
swapoff /dev/sda2
reboot

#--------------------------------------------------------------------------

useradd -m -g users -G wheel,storage,power,audio cyber
passwd cyber
EDITOR=vim visudo

        wheel ALL=(ALL) NOPASSWD: ALL
        %wheel ALL=(ALL) ALL

   # su - thinkpad
xdg-user-dirs-update
mkdir Sources
cd Sources
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
sudo vim /etc/pacman.conf
yay -S pa-applet-git
sudo pacman -S bluez bluez-utils blueman
sudo systemctl enable bluetooth
sudo pacman -S tlp tlp-rdw powertop acpi
sudo systemctl enable tlp
sudo systemctl enable tlp-sleep
sudo systemctl mask systemd-rfkill.service
sudo systemctl mask systemd-rfkill.socket
sudo pacman -S acpi_call

sudo systemctl enable fstrim.timer
sudo pacman -S xorg-server xorg-apps xorg-xinit
sudo pacman -S i3-gaps i3blocks i3lock numlockx
sudo pacman -S lightdm lightdm-gtk-greeter --needed
sudo systemctl enable lightdm
sudo pacman -S noto-fonts ttf-ubuntu-font-family ttf-dejavu ttf-freefont
sudo pacman -S ttf-liberation ttf-droid ttf-roboto terminus-font
sudo pacman -S rxvt-unicode ranger rofi dmenu --needed

sudo pacman -S firefox vlc --needed
sudo reboot
sudo pacman -S zsh
sudo pacman -S lxappearance
sudo pacman -S arc-gtk-theme
sudo pacman -S papirus-icon-theme
    

sudo vim /etc/lightdm/lightdm-gtk-greeter.conf

    [greeter]
    theme-name = Arc-Dark
    icon-theme-name = Papirus-Dark
    background = #2f343f

#--------------------------------------------------------------------------
