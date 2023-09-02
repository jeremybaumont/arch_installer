#!/bin/bash

# e - script stops on error
# u - error if undefined variable
# o pipefail - script fails if command piped fails
set -euo pipefail

url-arch-iso() {
    local -r iso_name="archlinux-x86_64.iso"
    local base_url=$(curl --silent https://archlinux.org/download/ | htmlq --attribute href a | grep 'aarnet.edu.au')
    echo "$base_url/$iso_name"
}

usb_disk() {
  echo "$device" 
}

dialog-what-usb-disk-to-use() {
    local file=${1:?}

    devices_list=$(lsblk -p -o KNAME,MOUNTPOINT | grep -E 'media' | cut -f1 -d ' ')
    dialog --title "Choose your usb drive" --no-cancel --radiolist \
        "Where do you want to write the linux arch iso?\n\n\
        Select with SPACE, valid with ENTER.\n\n\
        WARNING: Everything will be DESTROYED on the usb disk!" 15 60 4 "${devices_list[@]}" 2> "$file"
}


run() {
    local dry_run=${dry_run:-false}
    local output=${output:-/dev/tty2}

    while getopts d:o: option
    do
        case "${option}"
            in
            d) dry_run=${OPTARG};;
            o) output=${OPTARG};;
            *);;
        esac
    done

    log INFO "DRY RUN? $dry_run" "$output"

    local disk
    dialog-what-usb-disk-to-use dev
    disk=$(cat dev) && rm dev 
    log INFO "USB DISK CHOSEN: $disk" "$output"

}


run "$@"
