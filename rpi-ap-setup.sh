#!/bin/sh

# Raspberry Pi 3 Access Point setup
# Copyright (c) 2018 Alexandre Roman <alexandre.roman@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This script will automatically setup your Raspberry Pi 3 as a Wi-Fi access point,
# using integrated Wi-Fi controller.
# Use this script on a fresh install of Raspbian Stretch Lite.
# Once connected to the Wi-Fi network, all packets are redirected to the local
# Ethernet interface, so you may connect to the Internet.

# The following configuration will be set:
# - Wi-Fi SSID: rpinet
# - Wi-Fi password: changeme (you should really change it!)
# - Wi-Fi connection parameters: WPA2/PSK on channel 10
# - Network gateway: 192.168.100.1
# - IP network: 192.168.100.0/24
# - DHCP server range: 192.168.100.10/192.168.100.200
# - DNS servers: 8.8.8.8, 8.8.4.4 (from Google)

# You must be root to run this script:
# $ sudo su
# $ /bin/sh rpi-ap-setup.sh

# You must reboot your device to enable Wi-Fi access point.

if [ `id -u` != "0" ]; then
    echo "Please run this script as root."
    exit
fi

# Update distribution packages.
apt-get update
apt-get upgrade -y

# Update Raspberry Pi firmware.
rpi-update

# Install required packages:
# - hostapd: access point
# - udhcpd: lightweight DHCP server
apt-get install -y hostapd udhcpd

# Setup DHCP server.
cat <<EOF > /etc/udhcpd.conf
start           192.168.100.10
end             192.168.100.200
interface       wlan0
remaining       yes
opt     dns     8.8.8.8 8.8.4.4
opt     domain  rpinet
option  subnet  255.255.255.0
opt     router  192.168.100.1
option  lease   864000
EOF

# Enable DHCP server.
cat <<EOF > /etc/default/udhcpd
# Comment the following line to enable
#DHCPD_ENABLED="no"

# Options to pass to busybox' udhcpd.
#
# -S    Log to syslog
# -f    run in foreground

DHCPD_OPTS="-S"
EOF

# Disable DHCP client on wlan0 since we are using a static address.
cat <<EOF >> /etc/dhcpcd.conf
denyinterfaces wlan0
EOF

# Set a static address for wlan0.
cat <<EOF > /etc/network/interfaces.d/wlan0
allow-hotplug wlan0
iface wlan0 inet static
    address 192.168.100.1
    netmask 255.255.255.0
    network 192.168.100.0
EOF

# Setup Hostapd
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
driver=nl80211
ssid=rpinet
hw_mode=g
channel=6
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
ieee80211n=1
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=changeme
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Enable Hostapd.
cat <<EOF > /etc/default/hostapd
# Defaults for hostapd initscript
#
# See /usr/share/doc/hostapd/README.Debian for information about alternative
# methods of managing hostapd.
#
# Uncomment and set DAEMON_CONF to the absolute path of a hostapd configuration
# file and hostapd will be started during system boot. An example configuration
# file can be found at /usr/share/doc/hostapd/examples/hostapd.conf.gz
#
DAEMON_CONF="/etc/hostapd/hostapd.conf"

# Additional daemon options to be appended to hostapd command:-
#       -d   show more debug messages (-dd for even more)
#       -K   include key data in debug messages
#       -t   include timestamps in some debug messages
#
# Note that -B (daemon mode) and -P (pidfile) options are automatically
# configured by the init.d script and must not be added to DAEMON_OPTS.
#
#DAEMON_OPTS=""
EOF

# Activate IPv4 packet forwarding in kernel configuration.
cat <<EOF >> /etc/sysctl.conf
net.ipv4.ip_forward=1
EOF

# Setup packet forwarding.
iptables -F
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
iptables-save > /etc/iptables.ipv4.nat

# Enable packet forwarding when wlan0 is up.
cat <<EOF > /etc/network/if-up.d/wlan0
#!/bin/sh
# Enable network forwarding when Wi-Fi access point is up.

set -e

if [ "\$MODE" != start ]; then
    exit 0
fi

if [ "\$IFACE" = wlan0 ]; then
    iptables-restore < /etc/iptables.ipv4.nat
fi
exit 0
EOF

chmod +x /etc/network/if-up.d/wlan0

echo "You're done. Reboot this device to enjoy Wi-Fi access point."
