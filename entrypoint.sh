#!/bin/bash

# exit when any command fails
set -e

# create a tun device if not exist
# allow passing device to ensure compatibility with Podman
if [ ! -e /dev/net/tun ]; then
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# start dbus
sudo mkdir -p /run/dbus
if [ -f /run/dbus/pid ]; then
    sudo rm /run/dbus/pid
fi
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf

# start the daemon
sudo warp-svc --accept-tos &

# sleep to wait for the daemon to start, default 2 seconds
sleep "$WARP_SLEEP"

# if /var/lib/cloudflare-warp/reg.json not exists, setup new warp client
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    # if /var/lib/cloudflare-warp/mdm.xml not exists or REGISTER_WHEN_MDM_EXISTS not empty, register the warp client
    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "$REGISTER_WHEN_MDM_EXISTS" ]; then
        warp-cli registration new && echo "Warp client registered!"
        # if a license key is provided, register the license
        if [ -n "$WARP_LICENSE_KEY" ]; then
            echo "License key found, registering license..."
            warp-cli registration license "$WARP_LICENSE_KEY" && echo "Warp license registered!"
        fi
    fi
    # connect to the warp server
    warp-cli --accept-tos connect
else
    echo "Warp client already registered, skip registration"
fi

# disable qlog if DEBUG_ENABLE_QLOG is empty
if [ -z "$DEBUG_ENABLE_QLOG" ]; then
    warp-cli --accept-tos debug qlog disable
else
    warp-cli --accept-tos debug qlog enable
fi

# if WARP_ENABLE_NAT is provided, enable NAT and forwarding
if [ -n "$WARP_ENABLE_NAT" ]; then
    # switch to warp mode
    echo "[NAT] Switching to warp mode..."
    warp-cli --accept-tos mode warp
    warp-cli --accept-tos connect

    # wait another seconds for the daemon to reconfigure
    sleep "$WARP_SLEEP"

    # enable NAT
    echo "[NAT] Enabling NAT..."
    sudo nft add table ip nat
    sudo nft add chain ip nat WARP_NAT { type nat hook postrouting priority 100 \; }
    sudo nft add rule ip nat WARP_NAT oifname "CloudflareWARP" masquerade
    sudo nft add table ip mangle
    sudo nft add chain ip mangle forward { type filter hook forward priority mangle \; }
    sudo nft add rule ip mangle forward tcp flags syn tcp option maxseg size set rt mtu

    sudo nft add table ip6 nat
    sudo nft add chain ip6 nat WARP_NAT { type nat hook postrouting priority 100 \; }
    sudo nft add rule ip6 nat WARP_NAT oifname "CloudflareWARP" masquerade
    sudo nft add table ip6 mangle
    sudo nft add chain ip6 mangle forward { type filter hook forward priority mangle \; }
    sudo nft add rule ip6 mangle forward tcp flags syn tcp option maxseg size set rt mtu
fi


CONFIG='/etc/tinyproxy/tinyproxy.conf'
if [ ! -f "$CONFIG"  ]; then 
echo 'Port 8888' > $CONFIG
echo '#DisableViaHeader Yes' >> $CONFIG
echo '#StatHost "tinyproxy.stats"' >> $CONFIG
echo 'MaxClients 100' >> $CONFIG
echo 'Allow 127.0.0.1' >> $CONFIG
echo 'Allow ::1' >> $CONFIG
echo 'LogLevel Info' >> $CONFIG
echo 'Timeout 600' >> $CONFIG
echo '#BasicAuth user password' >> $CONFIG
sed -i "s|^Allow |#Allow |" "$CONFIG"
[    "$PORT" != "8888" ]                              && sed -i "s|^Port 8888|Port $PORT|" "$CONFIG"
[ -z "$DISABLE_VIA_HEADER" ]                          || sed -i "s|^#DisableViaHeader .*|DisableViaHeader Yes|" "$CONFIG"; \
[ -z "$STAT_HOST" ]                                   || sed -i "s|^#StatHost .*|StatHost \"${STAT_HOST}\"|" "$CONFIG"; \
[ -z "$MAX_CLIENTS" ]                                 || sed -i "s|^MaxClients .*|MaxClients $MAX_CLIENTS|" "$CONFIG"; \
[ -z "$ALLOWED_NETWORKS" ]                            || for network in $ALLOWED_NETWORKS; do echo "Allow $network" >> "$CONFIG"; done; \
[ -z "$LOG_LEVEL" ]                                   || sed -i "s|^LogLevel .*|LogLevel ${LOG_LEVEL}|" "$CONFIG"; \
[ -z "$TIMEOUT" ]                                     || sed -i "s|^Timeout .*|Timeout ${TIMEOUT}|" "$CONFIG"; \
[ -z "$AUTH_USER" ] || [ -z "$AUTH_PASSWORD" ]        || sed -i "s|^#BasicAuth .*|BasicAuth ${AUTH_USER} ${AUTH_PASSWORD}|" "$CONFIG"; \
[ -z "$AUTH_USER" ] || [ ! -f "$AUTH_PASSWORD_FILE" ] || sed -Ei "s|^#?BasicAuth .*|BasicAuth ${AUTH_USER} $(cat "$AUTH_PASSWORD_FILE")|" "$CONFIG"
sed -i 's|^LogFile |# LogFile |' "$CONFIG"; \
fi;

tinyproxy -d -c /etc/tinyproxy/tinyproxy.conf