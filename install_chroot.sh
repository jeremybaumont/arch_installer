#!/bin/bash

# e - script stops on error
# u - error if undefined variable
# o pipefail - script fails if command piped fails
set -euo pipefail

run() {
    output=$(cat /var_output)
    log INFO "FETCH VARS FROM FILES" "$output"
    uefi=$(cat /var_uefi)
    hd=$(cat /var_disk)
    hostname=$(cat /var_hostname)
    url_installer=$(cat /var_url_installer)
    encrypt=$(cat /var_encrypt)
    my_locale="en_US.UTF-8"
    my_lang="en"
    my_encoding="UTF-8"

    log INFO "INSTALL DIALOG" "$output"
    install-dialog

    log INFO "INSTALL BOOTLOADER" "$output"
    install-bootloader "$encrypt" "$hd" "$uefi" "$my_locale" "$my_lang"

    log INFO "SET HARDWARE CLOCK" "$output"
    set-hardware-clock

    log INFO "SET TIMEZONE" "$output"
    ln -sf /usr/share/zoneinfo/Australia/Sydney /etc/localtime
    hwclock --systohc

    log INFO "WRITE HOSTNAME: $hostname" "$output" \
    write-hostname "$hostname"

    log INFO "ADD HOSTNAME TO /etc/hosts: $hostname" "$output" \
    add-hostname-hosts "$hostname"

    log INFO "CONFIGURE LOCALE AND KEYBOARD LAYOUT" "$output"
    configure-locale-keymap "$my_locale" "$my_encoding" "$my_lang"

    log INFO "ADD ROOT" "$output"
    dialog --title "root password" --msgbox "It's time to add a password for the root user" 10 60
    config_user root

    log INFO "ADD USER" "$output"
    dialog --title "Add User" --msgbox "We can't always be root. Too many responsibilities. Let's create another user." 10 60

    config_user

    continue-install "$url_installer"
}

log() {
    local -r level=${1:?}
    local -r message=${2:?}
    local -r output=${3:?}
    local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    echo -e "${timestamp} [${level}] ${message}" >>"$output"
}

write-hostname() {
    local -r hostname=${1:?}
    echo "$hostname" > /etc/hostname
}

add-hostname-hosts() {
    local -r hostname=${1:?}
    sed -i 's/\(^[^#].*\)/\1'" $hostname"'/g' /etc/hosts
}

install-dialog() {
    pacman --noconfirm --needed -S dialog
}

install-grub() {
    local -r hd=${1:?}
    local -r uefi=${2:?}

    pacman -S --noconfirm grub

    if [ "$uefi" = 1 ]; then
        pacman -S --noconfirm efibootmgr
        grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
    else
        grub-install "$hd"
    fi

    grub-mkconfig -o /boot/grub/grub.cfg
}

install-systemd-boot() {
    local -r hd=${1:?}
    local -r uefi=${2:?}
    local -r locale=${3:?}
    local -r lang=${4:?}

    local boot_dir=/boot

    [[ "$uefi" == 1 ]] && boot_dir=/boot/efi

    hooks='HOOKS="base udev autodetect modconf block keyboard encrypt lvm2 filesystems fsck"'
    cp /etc/mkinitcpio.conf{,.bak}
    sed -i "s/^HOOKS=.*/$hooks/g" /etc/mkinitcpio.conf
    mkinitcpio -P
    bootctl --path="$boot_dir/" install
    write-boot-loader-configuration $boot_dir/loader/loader.conf
    write-boot-loader-arch-profile $hd $boot_dir/loader/entries/arch.conf $locale $lang
    write-boot-loader-arch-lts-profile $hd $boot_dir/loader/entries/arch-lts.conf $locale $lang
}

write-boot-loader-configuration() {
    local -r file=${1:?}

    cat <<EOF > "$file"
#timeout 3
#console-mode keep
default arch
timeout 5
console-mode max
editor 0
EOF
}

write-boot-loader-arch-profile(){
    local -r hd=${1:?}
    local -r file=${2:?}
    local -r locale=${3:?}
    local -r lang=${4:?}

    cat <<EOF > "$file"
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options cryptdevice=${hd}2:main root=/dev/mapper/main-root resume=/dev/mapper/main-swap lang=${lang} locale=${locale}
EOF
}

write-boot-loader-arch-lts-profile(){
    local -r hd=${1:?}
    local -r file=${2:?}
    local -r locale=${3:?}
    local -r lang=${4:?}

    cat <<EOF > "$file"
title           Arch Linux LTS
linux           /vmlinuz-linux-lts
initrd          /initramfs-linux-lts.img
options cryptdevice=${hd}2:main root=/dev/mapper/main-root resume=/dev/mapper/main-swap lang=${lang} locale=${locale}
EOF
}

install-bootloader() {
    local -r encrypt=${1:?}
    local -r hd=${2:?}
    local -r uefi=${3:?}
    local -r locale=${4:?}
    local -r lang=${5:?}

    if [ "$encrypt" = 1 ]; then
      # Not encrypted boot partition with grub
      [[ "$uefi" = 0 ]]  \
      && log INFO "INSTALL GRUB ON $hd WITH UEFI" "$output" \
      || log INFO "INSTALL GRUB ON $hd WITHOUT UEFI" "$output" \
      install-grub "$hd" "$uefi"

    else
      # Encrypted boot partition with systemd-boot
      [[ "$uefi" = 0 ]]  \
      && log INFO "INSTALL SYSTEMD-BOOT ON $hd WITH UEFI" "$output" \
      || log INFO "INSTALL SYSTEMD-BOOT ON $hd WITHOUT UEFI" "$output"
      install-systemd-boot "$hd" "$uefi" "$locale" "$lang"
    fi
}

set-timezone() {
    local -r tz=${1:?}
    timedatectl set-timezone "$tz"
}

set-hardware-clock() {
    hwclock --systohc
}

configure-locale-keymap() {
    local -r locale=${1:?}
    local -r encoding=${2:?}
    local -r keymap=${3:?}

    echo "$locale $encoding" >> /etc/locale.gen
    locale-gen
    echo "LANG=$locale" > /etc/locale.conf

    loadkeys $keymap
    echo "KEYMAP=$keymap" > /etc/vconsole.conf
}

config_user() {
    local name=${1:-none}

    if [ "$name" == none ]; then
        dialog --no-cancel --inputbox "Please enter your username" 10 60 2> name
        name=$(cat name) && rm name
    fi

    dialog --no-cancel --passwordbox "Enter your password" 10 60 2> pass1
    dialog --no-cancel --passwordbox "Enter your password again. To be sure..." 10 60 2> pass2

    while [ "$(cat pass1)" != "$(cat pass2)" ]
    do
        dialog --no-cancel --passwordbox "Passwords do not match.\n\nEnter password again." 10 60 2> pass1
        dialog --no-cancel --passwordbox "Retype password." 10 60 2> pass2
    done
    pass1=$(cat pass1)

    rm pass1 pass2

    # Create user if doesn't exist
    if [[ ! "$(id -u "$name" 2> /dev/null)" ]]; then
        dialog --infobox "Adding user $name..." 4 50
        useradd -m -g wheel -s /bin/bash "$name"
    fi

    # Add password to user
    echo "$name:$pass1" | chpasswd

    # Save name for later
    echo "$name" > /tmp/var_user_name
}

continue-install() {
    local -r url_installer=${1:?}

    dialog --title "Continue installation" --yesno "Do you want to setup network configuration?" 10 60 \
        && curl "$url_installer/install_network.sh" > /tmp/install_network.sh \
        && bash /tmp/install_network.sh
}

run "$@"
