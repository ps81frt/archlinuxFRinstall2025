# 🇫🇷 Arch Linux FR Install 2025

Script d'installation automatisée d'Arch Linux optimisé pour la France avec partitionnement intelligent et configuration complète.

## 📋 Sommaire

- [Caractéristiques](#-caractéristiques)
- [Prérequis](#-prérequis)
- [Installation rapide](#-installation-rapide)
- [Configuration des partitions](#-configuration-des-partitions)
- [Utilisation](#-utilisation)
- [Post-installation](#-post-installation)
- [Personnalisation](#-personnalisation)
- [Dépannage](#-dépannage)
- [Contribution](#-contribution)

## ✨ Caractéristiques

### 🎯 Installation automatisée
- Configuration française complète (clavier, locale, timezone)
- Partitionnement intelligent selon la taille du disque
- Installation EFI avec GRUB
- Configuration réseau automatique
- Environnement i3-gaps pré-configuré

### 🔧 Partitionnement adaptatif
- **≤ 128 GB** : Configuration optimisée pour petits disques
- **≤ 256 GB** : Configuration standard (recommandée)
- **≤ 512 GB** : Configuration généreuse
- **> 512 GB** : Configuration pour gros disques/serveurs

### 🖥️ Environnement graphique
- **WM** : i3-gaps avec i3blocks
- **DM** : LightDM avec thème Arc-Dark
- **Terminal** : rxvt-unicode
- **Launcher** : Rofi + dmenu
- **Thème** : Arc-Dark + Papirus icons

### 🛠️ Outils inclus
- **Développement** : git, vim, base-devel
- **Réseau** : NetworkManager, SSH
- **Audio** : PulseAudio + pavucontrol
- **Bluetooth** : bluez + blueman
- **Alimentation** : TLP pour laptops
- **AUR** : yay helper pré-installé

## 🔧 Prérequis

- Clé USB bootable avec Arch Linux ISO
- Connexion Internet active
- Disque dur ≥ 64 GB
- Système UEFI (EFI)

## 🚀 Installation rapide

```bash
# 1. Télécharger le script
curl -L https://raw.githubusercontent.com/ps81frt/archlinuxfr/main/install.sh -o install.sh

# 2. Rendre exécutable
chmod +x install.sh

# 3. Lancer l'installation
./install.sh
```

## 💾 Configuration des partitions

### Détection automatique des tailles

| Taille disque | EFI | SWAP | ROOT | HOME | DATA |
|---------------|-----|------|------|------|------|
| ≤ 128 GB      | 1G  | 2G   | 30G  | *intégré* | Reste |
| ≤ 256 GB      | 1G  | 4G   | 50G  | Auto | ~25G |
| ≤ 512 GB      | 1G  | 8G   | 60G  | 200G | Reste |
| > 512 GB      | 1G  | 16G  | 80G  | 300G | Reste |

### Options de partitionnement

1. **Automatique** ⚡ (recommandé)
   - Détection de la taille du disque
   - Partitionnement optimal automatique
   - Aucune interaction requise

2. **Manuel** 🔧
   - Contrôle total avec gdisk
   - Guide étape par étape
   - Pour utilisateurs avancés

3. **Passer** ⏭️
   - Utilise les partitions existantes
   - Pour réinstallations

## 📖 Utilisation

### Étape 1 : Préparation

```bash
# Boot sur la clé USB Arch Linux
# Configurer le clavier français
loadkeys fr

# Vérifier la connexion Internet
ping google.com
```

### Étape 2 : Lancement

```zsh
# Télécharger et lancer le script
curl -L https://git.io/archfr2025 | bash
```

### Étape 3 : Choix du partitionnement

Le script vous proposera :
```
=== CHOIX DU PARTITIONNEMENT ===
1) Partitionnement automatique (recommandé)
2) Partitionnement manuel avec gdisk  
3) Passer (partitions déjà créées)

Votre choix [1-3]:
```

### Étape 4 : Installation automatique

Le script effectue automatiquement :
- Formatage des partitions
- Installation du système de base
- Configuration locale française
- Installation de GRUB
- Configuration réseau
- Création de l'utilisateur

### Étape 5 : Post-installation

Après redémarrage, connectez-vous et le script continue :
- Installation de l'environnement graphique
- Configuration des thèmes
- Installation des applications

## 🎨 Post-installation

### Applications installées

**Système :**
- Firefox (navigateur)
- VLC (lecteur multimédia)
- Ranger (gestionnaire de fichiers)
- htop (moniteur système)

**Développement :**
- git, vim
- yay (AUR helper)
- base-devel

**Personnalisation :**
- lxappearance (thèmes GTK)
- Arc-Dark theme
- Papirus icons

### Configuration manuelle

```bash
# Changer le shell par défaut
chsh -s /bin/zsh

# Configurer Git
git config --global user.name "Votre Nom"
git config --global user.email "email@example.com"

# Installer des applications supplémentaires
yay -S code discord steam
```

## 🔧 Personnalisation

### Modifier les tailles de partitions

Éditez la fonction `auto_partition()` dans le script :

```bash
# Exemple pour disque 256GB personnalisé
ROOT_SIZE="40G"    # au lieu de 50G
HOME_SIZE="150G"   # au lieu de calculé
```

### Changer l'environnement graphique

Remplacez la section i3 par votre WM préféré :

```bash
# Exemple pour XFCE
sudo pacman -S xfce4 xfce4-goodies
```

### Applications supplémentaires

Ajoutez vos applications dans la section post-installation :

```bash
# Vos applications préférées
sudo pacman -S gimp libreoffice thunderbird
```

## 🔍 Dépannage

### Problèmes courants

**Erreur de partitionnement :**
```bash
# Vérifier les partitions
lsblk
fdisk -l
```

**Problème de boot :**
```bash
# Réinstaller GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

**Pas de réseau :**
```bash
# Redémarrer NetworkManager
sudo systemctl restart NetworkManager
```

### Logs d'installation

```bash
# Vérifier les logs du système
journalctl -b
```

## 📁 Structure du projet

```
archlinuxFRinstall2025/
├── install.sh          # Script principal
├── README.md           # Documentation
├── configs/            # Fichiers de configuration
│   ├── i3/            # Config i3
│   ├── lightdm/       # Config LightDM
│   └── dotfiles/      # Dotfiles
└── docs/              # Documentation supplémentaire
```

## 🤝 Contribution

Les contributions sont les bienvenues ! 

1. **Fork** le projet
2. **Créer** une branche feature (`git checkout -b feature/amazing-feature`)
3. **Commit** vos changements (`git commit -m 'Add amazing feature'`)
4. **Push** vers la branche (`git push origin feature/amazing-feature`)
5. **Ouvrir** une Pull Request

### Règles de contribution

- Tester sur une VM avant de proposer
- Commenter le code ajouté
- Respecter le style de code existant
- Mettre à jour la documentation

## 📝 Changelog

### Version 2025.1
- Partitionnement adaptatif selon la taille du disque
- Menu interactif pour le choix du partitionnement
- Support des disques de 64GB à 2TB+
- Configuration française complète
- Environnement i3-gaps pré-configuré

## 📜 Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.

## 🙏 Remerciements

- [Arch Linux](https://archlinux.org/) pour cette distribution exceptionnelle
- La communauté Arch pour la documentation
- [Arch Linux FR Forums](https://forums.archlinux.fr) pour l'entraide francophone
- Les contributeurs de ce projet

## 📞 Support

- **Issues** : [GitHub Issues](https://github.com/ps81frt/archlinuxFRinstall2025/issues)
- **Discussions** : [GitHub Discussions](https://github.com/ps81frt/archlinuxFRinstall2025/discussions)
- **Wiki Arch** : [Arch Wiki FR](https://wiki.archlinux.fr/)

---

⭐ **N'oubliez pas de donner une étoile si ce projet vous aide !**
