
## run as root

password="$1"
if [ "$password" = "" ]; then
    echo "usage: $0 <password>" >&2
    cat <<EOF >&2

Configures IPMI to be accessible via the network.

To reset $host:
    ipmitool -H ${host}ipmi -U root -P $password power reset

To power cycle:
    ipmitool -H ${host}ipmi -U root -P $password power cycle

Other "power" commands are "off", "on", and "status".

To access the console:
    ipmitool -H ${host}ipmi -U root -P $password -Ilanplus sol activate

EOF
    exit 1
fi
if [ `whoami` != "root" ]; then
    echo "$0 must be run as root" >&2
    exit 1
fi

apt-get install ipmitool
modprobe ipmi_devintf

## user id 2 is root
ipmitool user set name 2 "root"
ipmitool user set password 2 "$password"

## replace 38400 with 115200 if BIOS settings have been changed
## run a getty on the serial console for testing
cat <<EOF > /etc/init/ttyS1.conf
# ttyS1 - getty
#
# This service maintains a getty on ttyS1 from the point the system is
# started until it is shut down again.

start on runlevel [23] and (
            not-container or
            container CONTAINER=lxc or
            container CONTAINER=lxc-libvirt)

stop on runlevel [!23]

respawn
exec /sbin/getty -8 38400 ttyS1
EOF

start ttyS1

sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS1,38400n8"/' /etc/default/grub
update-grub
