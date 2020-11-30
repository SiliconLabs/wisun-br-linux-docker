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

print_usage()
{
    cat << EOF >&2
Usage: $1 [OPTIONS] [MODE]

Options:
  -d, --device=DEVICE  UART device to use (default: /dev/ttyACM0)
  -D, --dhcp           Configure IPv4 using DHCP
  -s, --shell          Launch a shell on launch
  -h, --help           Show this help

Modes:
  local    Only nodes to be configured and communicate with the docker instance.
  proxy    Run a proxy allowing to communicate with local network
  auto     Detect if a local IPv6 network is availabe and launch \`local' or
           \`proxy' accordingly.
EOF
    [ "$2" ] && exit $2
}

check_privilege()
{
    ip link add dummy0 type dummy 2> /dev/null || \
        die "Not enough privilege to run (missing --privileged?)"
    ip link delete dummy0
}

launch_dhcpc()
{
    if [ "$LAUNCH_DHCPC" ]; then
        umount /etc/resolv.conf
        udhcpc -i eth0
    fi
}

launch_tunslip6()
{
    IPV6_IP=$1
    [ -e "$UART" ] || die "Failed to detect $UART"

    echo " ---> [1mLaunch tunslip6 on $UART[0m"
    tunslip6 -s $UART -B 115200 $IPV6_IP &
    for i in $(seq 10); do
        ip -6 addr show tun0 | grep -q $IPV6_IP && break
        sleep 0.2
    done
}

launch_radvd()
{
    IPV6_NET=$1

    echo " ---> [1mLaunch radvd on $IPV6_NET[0m"
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

launch_ndppd()
{
    IPV6_NET=$1

    echo " ---> [1mLaunch ndppd on $IPV6_NET[0m"
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

launch_last_process()
{
    echo " ---> [1mResult of 'ip -6 addr':[0m"
    ip -6 addr
    if [ "$LAUNCH_SHELL" ]; then
        echo " ---> [1mLaunch sh[0m"
        echo "Note: \"docker exec -it <CONTAINER> sh\" is a better alternative"
        exec sh
    else
        tail -f /dev/null
    fi
}

run_proxy()
{
    sysctl -q net.ipv6.conf.default.disable_ipv6=0
    sysctl -q net.ipv6.conf.all.disable_ipv6=0
    sysctl -q net.ipv6.conf.default.forwarding=1
    sysctl -q net.ipv6.conf.all.forwarding=1
    sysctl -q net.ipv6.conf.default.accept_ra=2
    sysctl -q net.ipv6.conf.eth0.accept_ra=2

    launch_dhcpc
    for i in $(seq 10); do
        ip -6 addr show eth0 | grep -q global && break
        sleep 0.2
    done
    IPV6_NET=$(rdisc6 -r 5 -w 300 -q -1 eth0)
    [ "$IPV6_NET" ] || die "Failed to get IPv6 address"

    launch_tunslip6 fd01::1/64
    # tunslip6 add these addresses but it is useless
    ip addr del dev tun0 fe80::1/64
    ip addr del dev tun0 fd01::1/64
    launch_radvd $IPV6_NET
    launch_ndppd $IPV6_NET
    launch_last_process
}

run_local()
{
    sysctl -q net.ipv6.conf.default.disable_ipv6=0
    sysctl -q net.ipv6.conf.all.disable_ipv6=0
    sysctl -q net.ipv6.conf.default.forwarding=1
    sysctl -q net.ipv6.conf.all.forwarding=1
    sysctl -q net.ipv6.conf.default.accept_ra=2
    sysctl -q net.ipv6.conf.all.accept_ra=2

    launch_tunslip6 fd01::1/64
    # tunslip6 add this address but it is useless
    ip addr del dev tun0 fe80::1/64
    launch_radvd ::/64
    launch_last_process
}

run_auto()
{
    sysctl -q net.ipv6.conf.eth0.accept_ra=2
    sysctl -q net.ipv6.conf.eth0.disable_ipv6=0

    HAVE_IPV6=
    for i in $(seq 20); do
        ip -6 addr show eth0 | grep -q global && HAVE_IPV6=1 && break
        sleep 0.2
    done
    if [ "$HAVE_IPV6" ]; then
        echo " ---> [1mFound IPv6 network[0m"
        run_proxy
    else
        echo " ---> [1mNo network found[0m"
        run_local
    fi
}

check_privilege

OPTS=$(getopt -l device:,dhcp,shell,help -- d:Dsh "$@") || exit 1
eval set -- "$OPTS"
while true; do
    case "$1" in
        -s|--shell)
            LAUNCH_SHELL=1
            shift 1
            ;;
        -D|--dhcp)
            LAUNCH_DHCPC=1
            shift 1
            ;;
        -d|--device)
            UART=$2
            shift 2
            ;;
        -h|--help)
            print_usage $0
            exit 0
            ;;
        --)
            shift
            break
            ;;
    esac
done

case "$1" in
    auto|"")
        run_auto
        ;;
    local)
        run_local
        ;;
    proxy)
        run_proxy
        ;;
    *)
        print_usage $0
        exit 1
esac
