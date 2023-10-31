#!/bin/bash

# e - script stops on error
# u - error if undefined variable
# o pipefail - script fails if command piped fails
set -euo pipefail

run() {
    output=$(cat /var_output)
    log INFO "FETCH VARS FROM FILES" "$output"
    url_installer=$(cat /var_url_installer)

    log INFO "INSTALL PACKAGES" "$output"
    install-network-packages

    log INFO "INSTALL IWD" "$output"
    install-iwd

    log INFO "INSTALL NETWORKMANAGER" "$output"
    install-networkmanager

    log INFO "CONNECT WIFI" "$output"
    dialog --title "CONNECT WIFI" --msgbox "It's time to connect to WIFI!" 10 60
    dialog-what-essid-to-use essid
    essid=$(cat essid) && rm essid
    log INFO "ESSID: $essid" "$output"
    connect-to-wifi "$essid"

    log INFO "INSTALL SYSTEMD-RESOLVED" "$output"
    install-systemd-resolved
    
    continue-install "$url_installer"
}

log() {
    local -r level=${1:?}
    local -r message=${2:?}
    local -r output=${3:?}
    local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    echo -e "${timestamp} [${level}] ${message}" >>"$output"
}

install-network-packages() {
    pacman --noconfirm --needed -S iwd networkmanager systemd
}

write-iwd-configuration() {
    local -r file=${1:?}

    cat <<EOF > "$file"
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF
}

install-iwd() {
    write-iwd-configuration /etc/iwd/main.conf
    systemctl enable iwd
    systemctl start iwd
    iwctl adapter wlan0 set-property Powered on
    iwctl station wlan0 scan
    iwctl station wlan0 get-networks
}

install-networkmanager() {
    systemctl enable NetworkManager
    systemctl start NetworkManager
}

install-systemd-resolved() {
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    systemctl enable systemd-resolved
    systemctl start systemd-resolved
}

dialog-what-essid-to-use() {
    local file=${1:?}

    essid_list=($(iwctl station wlan0 get-networks | grep psk  | awk -F'psk' '{print $1}' | awk '{$1=$1;print}'))
    dialog --title "Choose your essid" --no-cancel --radiolist \
        "Where do you want to connect your WIFI?\n\n\
        Select with SPACE, valid with ENTER." 15 60 4 "${essid_list[@]}" 2> "$file"
}

connect-to-wifi() {
    local essid=${1:-none}

    if [ "$essid" == none ]; then
        dialog --no-cancel --inputbox "Please enter your essid" 10 60 2> essid
        essid=$(cat essid) && rm essid
    fi

    dialog --no-cancel --passwordbox "Enter wifi password for ${essid}" 10 60 2> pass
    pass=$(cat pass)
    rm pass 

    nmcli device wifi connect "${essid}" password "${pass}"
}

continue-install() {
    local -r url_installer=${1:?}

    dialog --title "Continue installation" --yesno "Do you want to install all the softwares and the dotfiles?" 10 60 \
        && curl "$url_installer/install_apps.sh" > /tmp/install_apps.sh \
        && bash /tmp/install_apps.sh
}
