#!/bin/bash
# Author  : ShHawk alias Alexandre Uzan
# Sujet : Environnement Sécurisé 

set -euo pipefail
export PATH="$PATH:/sbin:/usr/sbin"

# Vérifications globales
(( EUID == 0 )) || { echo "[Erreur] exécuter en root"; exit 1; }
for cmd in cryptsetup mkfs.ext4 mount umount fallocate dd losetup lsblk df blkid; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[Erreur] $cmd manquant"; exit 1; }
done

# Variables
DEFAULT_SIZE="5G"
CONTAINER="$HOME/env.img"
LOOP_FILE="$HOME/env.loop"
MAPPING="env_sec"
MOUNT_POINT="$HOME/env_mount"

# Prépare les dossiers
mkdir -p "${CONTAINER%/*}" "$MOUNT_POINT"

# Affichages
show_lsblk() { echo; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; echo; }
show_df()    { df -Th | grep -E "$MAPPING|Filesystem"; echo; }
show_blkid() { blkid /dev/mapper/"$MAPPING" 2>/dev/null || echo "(pas de mapping ouvert)"; echo; }

# Utilitaires
read_size_and_pass() {
  read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " SIZE
  SIZE=${SIZE:-$DEFAULT_SIZE}
  read -s -p "Mot de passe LUKS : " PASS; echo
  read -s -p "Confirmer le mot de passe : " PASS2; echo
  [[ "$PASS" == "$PASS2" ]] || { echo "[Erreur] mots de passe différents"; exit 1; }
}

attach_loop() {
  LOOPDEV=$(losetup --find --show "$CONTAINER")
  echo "$LOOPDEV" >"$LOOP_FILE"
}

detach_loop() {
  [[ -f "$LOOP_FILE" ]] && {
    losetup -d "$(cat "$LOOP_FILE")"
    rm -f "$LOOP_FILE"
  }
}

unlock_volume() {
  printf '%s' "$PASS" | cryptsetup open --type luks1 --key-file=- "$1" "$MAPPING"
}

lock_volume() {
  cryptsetup close "$MAPPING"
}

format_volume() {
  mkfs.ext4 /dev/mapper/"$MAPPING"
}

mount_volume() {
  mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
}

umount_volume() {
  umount "$MOUNT_POINT" 2>/dev/null || :
}

# Commandes
install() {
  echo ">>> INSTALL environnement <<<"
  show_lsblk

  read_size_and_pass
  [[ -f "$CONTAINER" ]] && { echo "[Erreur] conteneur existe"; exit 1; }
  cryptsetup status "$MAPPING" &>/dev/null && { echo "[Erreur] mapping existe"; exit 1; }

  # créer fichier
  if ! fallocate -l "$SIZE" "$CONTAINER" 2>/dev/null; then
    COUNT=${SIZE%[GgMm]}
    [[ "$SIZE" =~ [Gg]$ ]] && COUNT=$((COUNT*1024))
    dd if=/dev/zero of="$CONTAINER" bs=1M count="$COUNT" status=progress
  fi
  show_lsblk

  # boucle + LUKS
  attach_loop; show_lsblk
  printf '%s' "$PASS" | cryptsetup luksFormat --type luks1 --batch-mode "$LOOPDEV" --key-file=-
  show_lsblk

  # déverrouille, formate, monte
  unlock_volume "$LOOPDEV"; show_lsblk
  format_volume; show_lsblk
  mount_volume; show_lsblk; show_df; show_blkid

  echo "[GOOD] env installé et monté sur $MOUNT_POINT"
}

open() {
  echo ">>> OPEN environnement <<<"
  show_lsblk
  [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur"; exit 1; }

  [[ -f "$LOOP_FILE" ]] || attach_loop
  if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
    read -s -p "Mot de passe LUKS : " PASS; echo
    unlock_volume "$(cat "$LOOP_FILE")"
    echo "[GOOD] mapping créé"
  else
    echo "mapping déjà ouvert"
  fi
  show_lsblk

  if ! mountpoint -q "$MOUNT_POINT"; then
    mount_volume && echo "[GOOD] monté sur $MOUNT_POINT"
  else
    echo "point de montage déjà utilisé"
  fi
  show_lsblk; show_df
}

close() {
  echo ">>> CLOSE environnement <<<"
  show_lsblk

  umount_volume && echo "[GOOD] démonté"
  [[ -e /dev/mapper/"$MAPPING" ]] && (lock_volume && echo "[GOOD] verrouillé")
  detach_loop && echo "[GOOD] loop détaché"
  show_lsblk
}

delete() {
  echo ">>> DELETE environnement <<<"
  close || :
  [[ -f "$CONTAINER" ]] && rm -f "$CONTAINER" && echo "[GOOD] conteneur supprimé"
  rmdir "$MOUNT_POINT" 2>/dev/null || :
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
  delete)  delete ;;
  *) usage ;;
esac
