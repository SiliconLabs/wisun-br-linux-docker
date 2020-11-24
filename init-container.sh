#!/bin/sh
# vim: set sw=4 expandtab:
#
# Licence: GPLv2
# Created: 2020-11-18 15:37:16+01:00
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
# turn on bash's job control
set -m

UART=/dev/ttyACM0

die()
{
    echo "$@" >&2
    exit 1
}

launch_tunslip6()
{
    IPV6_IP=$1
    [ -e "$UART" ] || die "Failed to detect $UART"

    echo "** [1mLaunch tunslip6 on $UART[0m"
    tunslip6 -s $UART -B 115200 $IPV6_IP &
    for i in $(seq 10); do
        ip -6 addr show tun0 | grep -q $IPV6_IP && break
        sleep 0.2
    done
}

launch_radvd()
{
    IPV6_NET=$1

    echo "** [1mLaunch radvd on $IPV6_NET[0m"
cat << EOF > /etc/radvd.conf
interface tun0 {
    AdvSendAdvert on;
    IgnoreIfMissing on;
    prefix $IPV6_NET {
    };
};
EOF
    radvd --logmethod stderr
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

launch_ndppd()
{
    IPV6_NET=$1

    echo "** [1mLaunch ndppd on $IPV6_NET[0m"
    cat << EOF > /etc/ndppd.conf
proxy eth0 {
    autowire yes
    rule $IPV6_NET {
        iface tun0
    }
}

proxy tun0 {
    autowire yes
    rule $IPV6_NET {
        iface eth0
    }
}
EOF
    ndppd -d
}

case "$1" in
    local)
        run_local
        ;;
    *)
        echo "usage: $0 [local]"
esac
