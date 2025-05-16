#!/bin/bash
# Author : ShHawk 
# Sujet : Envirronnement Sécurisé

set -euo pipefail
export PATH="$PATH:/sbin:/usr/sbin"

# Vérifications  
(( EUID == 0 )) || { echo "[Erreur] exécuter en root"; exit 1; }
for cmd in cryptsetup mkfs.ext4 mount umount fallocate dd lsblk df blkid; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[Erreur] $cmd manquant"; exit 1; }
done

# variable 
DEFAULT_SIZE="5G"
CONTAINER="$HOME/environnement.img"
MAPPING="environnement"
MOUNT_POINT="$HOME/environnement_mount"

# préparer dossiers
CONTAINER_DIR="${CONTAINER%/*}"
[[ -d "$CONTAINER_DIR" ]] || mkdir -p "$CONTAINER_DIR"
[[ -d "$MOUNT_POINT" ]]    || mkdir -p "$MOUNT_POINT"

# Affichage de l’état des devices 
show_lsblk() {
  echo
  echo "=== lsblk ==="
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo
}

show_df() {
  echo
  echo "=== df -Th ==="
  df -Th | grep -E "$MAPPING|Filesystem"
  echo
}

show_blkid() {
  echo
  echo "=== blkid /dev/mapper/$MAPPING ==="
  blkid /dev/mapper/"$MAPPING" 2>/dev/null || echo "(pas de mapping ouvert)"
  echo
}

#install
install() {
  echo ">>> INSTALL ENVIRONNEMENT <<<"
  show_lsblk

  read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " size
  size=${size:-$DEFAULT_SIZE}

  read -s -p "Passphrase LUKS : " pass; echo
  read -s -p "Confirmer la passphrase : " pass2; echo
  [[ "$pass" != "$pass2" ]] && { echo "[Erreur] mots de passe différents"; exit 1; }

  [[ -f "$CONTAINER" ]] && { echo "[Erreur] $CONTAINER existe déjà"; exit 1; }
  cryptsetup status "$MAPPING" &>/dev/null && { echo "[Erreur] /dev/mapper/$MAPPING existe déjà"; exit 1; }

  echo "Création de $CONTAINER de taille $size..."
  if fallocate -l "$size" "$CONTAINER" 2>/dev/null; then :; else
    if [[ "$size" =~ [Gg]$ ]]; then cnt=$(echo "${size%?}*1024" | bc); else cnt=${size%M}; fi
    dd if=/dev/zero of="$CONTAINER" bs=1M count="$cnt" status=progress
  fi
  show_lsblk

  echo "Initialisation LUKS (tapez YES)…"
  printf '%s' "$pass" | cryptsetup luksFormat --type luks1 --batch-mode "$CONTAINER" --key-file=-
  show_lsblk

  echo "Ouverture du volume…"
  printf '%s' "$pass" | cryptsetup open --type luks1 --key-file=- "$CONTAINER" "$MAPPING"
  show_lsblk

  echo "Formatage ext4…"
  mkfs.ext4 /dev/mapper/"$MAPPING"
  show_lsblk

  echo "Montage sur $MOUNT_POINT…"
  mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
  show_lsblk
  show_df
  show_blkid

  echo "[GOOD] environnement installé et monté sur $MOUNT_POINT"
}

# OPEN
open() {
  echo ">>> OPEN ENVIRONNEMENT <<<"
  show_lsblk

  [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur, lancez 'install'"; exit 1; }

  if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
    read -s -p "Passphrase LUKS : " pass; echo
    printf '%s' "$pass" | cryptsetup open --type luks1 --key-file=- "$CONTAINER" "$MAPPING"
    echo "[GOOD] mapping /dev/mapper/$MAPPING créé"
  else
    echo "mapping déjà déverrouillé"
  fi
  show_lsblk

  if ! mountpoint -q "$MOUNT_POINT"; then
    mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
    echo "[GOOD] monté sur $MOUNT_POINT"
  else
    echo "point de montage déjà utilisé"
  fi
  show_lsblk
  show_df
}

#close
close() {
  echo ">>> CLOSE ENVIRONNEMENT <<<"
  show_lsblk

  if mountpoint -q "$MOUNT_POINT"; then
    umount "$MOUNT_POINT"
    echo "[GOOD] démonté $MOUNT_POINT"
  else
    echo "rien à démonter"
  fi
  show_lsblk

  if cryptsetup status "$MAPPING" &>/dev/null; then
    cryptsetup close "$MAPPING"
    echo "[GOOD] verrouillé /dev/mapper/$MAPPING"
  else
    echo "mapping déjà fermé"
  fi
  show_lsblk
}

#delete
delete() {
  echo ">>> DELETE environnement <<<"

  # fermer si monté/open
  close || true

  # suppression du conteneur
  if [[ -f "$CONTAINER" ]]; then
    rm -f "$CONTAINER"
    echo "[GOOD] supprimé $CONTAINER"
  else
    echo "pas de fichier conteneur à supprimer"
  fi

  # suppression du point de montage
  if [[ -d "$MOUNT_POINT" ]]; then
    rmdir "$MOUNT_POINT" 2>/dev/null && echo "[GOOD] supprimé $MOUNT_POINT" || echo "ne peut pas supprimer $MOUNT_POINT"
  fi

  show_lsblk
}

usage() {
  echo "Usage: $0 {install|open|close|delete}"
  exit 1
}

[[ $# -ne 1 ]] && usage
case "$1" in
  install) install ;;
  open)    open    ;;
  close)   close   ;;
  delete)  delete  ;;
  *) usage ;;
esac
