#!/bin/sh
# vim: set sw=4 expandtab:
#
# Licence: GPLv2
# Created: 2020-11-18 15:37:16+01:00
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#

launch_tunslip6()
{
    exec tunslip6 -s /dev/ttyUSB0 -B 115200 "$@"
}

run_local()
{
    sysctl net.ipv6.conf.default.disable_ipv6=0
    sysctl net.ipv6.conf.all.forwarding=1
    cat << EOF > /etc/radvd.conf
interface tun0 {
    AdvSendAdvert on;
    IgnoreIfMissing on;
    prefix ::/64 {
    };
};
EOF
    radvd --logmethod stderr
    launch_tunslip6 fd00::1
}

case "$1" in
    local)
        run_local
        ;;
    *)
        echo "usage: $0 [local]"
esac
