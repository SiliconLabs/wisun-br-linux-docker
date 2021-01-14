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

Setup the docker containter to create a WiSun Border Router.

Options:
  -d, --device=DEVICE UART device to use (default: /dev/ttyACM0).
  -D, --dhcp          Configure IPv4 using DHCP. Use it if you rely on a
                      network interface with macvlan driver.
  -r, --advert-route  Advertise the new route on eth0. Only work with the subnet
                      mode. Most of the hosts won't accept le route unless the
                      parameter accept_ra_rt_info_max_plen is at least the size
                      of the advertised prefix size. You may use it if the
                      router of your network is not able manage the new route
                      itself.
  -s, --shell         Launch a shell on startup.
  -h, --help          Show this help.

Modes:
  local           The nodes will be only able to communicate with the docker
                  instance using a random site-local prefix.
  site_local      Advertise a random site-local prefix and run a proxy. Local
                  workstations will retrieve an IPv6 address allowing them to
                  communicate with WiSun nodes.
  proxy           Re-use the local IPv6 prefix to configure WiSun nodes.
  subnet [PREFIX] Use PREFIX to configure WiSun nodes. PREFIX should come from
                  configuration of the parent router. If PREFIX is not defined,
                  generate a random site-local one.
  auto            Detect if a local IPv6 network is availabe and launch
                  \`site_local' or \`proxy' accordingly.

Note that random site-local prefixes are not routable (ie. you can't access
outside with these).

Examples:

  Provide minimal infrastructure to configure WiSun device through a Border
  Router connected on /dev/ttyUSB0:

    $1 -d /dev/ttyUSB0 local

  Parent router is correctly configured to delegate prefix
  2a01:e35:2435:66a1::/64 to my docker container:

    $1 subnet 2a01:e35:2435:66a1::1/64

  You want to test prefix delegation with a random prefix:

    other_host> sysctl net.ipv6.conf.eth0.accept_ra_rt_info_max_plen=128
    this_host> $1 subnet -r
EOF
    [ "$2" ] && exit $2
}

get_random_prefix()
{
    N1=$(dd bs=1 count=1 if=/dev/urandom 2> /dev/null | od -A n -t x1)
    N2=$(dd bs=2 count=1 if=/dev/urandom 2> /dev/null | od -A n -t x2)
    N3=$(dd bs=2 count=1 if=/dev/urandom 2> /dev/null | od -A n -t x2)
    N4=$(dd bs=2 count=1 if=/dev/urandom 2> /dev/null | od -A n -t x2)
    echo $N1:$N2:$N3:$N4 | tr -d ' '
}

check_privilege()
{
    ip link add dummy0 type dummy 2> /dev/null || \
        die "Not enough privilege to run (missing --privileged?)"
    ip link delete dummy0
}

launch_dhcpc()
{
    umount /etc/resolv.conf
    udhcpc -i eth0
}

launch_tunslip6()
{
    HAS_ARG=$1
    IPV6_IP=${1:-fd01::1/64}
    [ -e "$UART" ] || die "Failed to detect $UART"

    echo " ---> [1mLaunch tunslip6 on $UART[0m"
    tunslip6 -s $UART -B 115200 $IPV6_IP &
    for i in $(seq 10); do
        ip -6 addr show tun0 | grep -q $IPV6_IP && break
        sleep 0.2
    done
    if [ ! "$HAS_ARG" ]; then
        # tunslip6 add these addresses but it is useless.
        ip addr del dev tun0 fe80::1/64
        ip addr del dev tun0 fd01::1/64
    else
        # tunslip6 add this address but it is useless
        #ip addr del dev tun0 fe80::1/64
        true
    fi
}

launch_radvd()
{
    IPV6_NET=$1
    EXT_BEHAVIOR=$2

    echo " ---> [1mLaunch radvd on $IPV6_NET[0m"
    cat << EOF > /etc/radvd.conf
interface tun0 {
    AdvSendAdvert on;
    IgnoreIfMissing on;
    prefix $IPV6_NET { };
};
EOF
    case "$EXT_BEHAVIOR" in
        adv_prefix)
            cat << EOF >> /etc/radvd.conf
interface eth0 {
    AdvSendAdvert on;
    AdvDefaultLifetime 0;
    prefix $IPV6_NET { };
};
EOF
            ;;
        adv_route)
            cat << EOF >> /etc/radvd.conf
interface eth0 {
    AdvSendAdvert on;
    AdvDefaultLifetime 0;
    route $IPV6_NET {
        AdvRouteLifetime 1800;
    };
};
EOF
            ;;
        "")
            ;;
        *)
            die "internal error: unknown options: $EXT_BEHAVIOR"
            ;;
    esac
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
    sysctl -q net.ipv6.conf.all.accept_ra=2

    for i in $(seq 10); do
        ip -6 addr show eth0 | grep -q global && break
        sleep 0.2
    done
    IPV6_NET=$(rdisc6 -r 5 -w 300 -q -1 eth0)
    [ "$IPV6_NET" ] || die "Failed to get IPv6 address"

    launch_tunslip6 $IPV6_NET
    launch_radvd $IPV6_NET
    launch_ndppd $IPV6_NET
    launch_last_process
}

run_site_local()
{
    sysctl -q net.ipv6.conf.default.disable_ipv6=0
    sysctl -q net.ipv6.conf.all.disable_ipv6=0
    sysctl -q net.ipv6.conf.default.forwarding=1
    sysctl -q net.ipv6.conf.all.forwarding=1
    sysctl -q net.ipv6.conf.default.accept_ra=2
    sysctl -q net.ipv6.conf.all.accept_ra=2

    SITE_PREFIX=$(get_random_prefix)
    launch_tunslip6 fd$SITE_PREFIX::1/64
    launch_radvd fd$SITE_PREFIX::/64 adv_prefix
    launch_ndppd fd$SITE_PREFIX::/64
    launch_last_process
}

run_local()
{
    sysctl -q net.ipv6.conf.default.disable_ipv6=0
    sysctl -q net.ipv6.conf.all.disable_ipv6=0
    sysctl -q net.ipv6.conf.default.accept_ra=2
    sysctl -q net.ipv6.conf.all.accept_ra=2

    SITE_PREFIX=$(get_random_prefix)
    launch_tunslip6 fd$SITE_PREFIX::1/64
    launch_radvd fd$SITE_PREFIX::/64
    launch_last_process
}

run_subnet()
{
    sysctl -q net.ipv6.conf.default.disable_ipv6=0
    sysctl -q net.ipv6.conf.all.disable_ipv6=0
    sysctl -q net.ipv6.conf.default.forwarding=1
    sysctl -q net.ipv6.conf.all.forwarding=1
    sysctl -q net.ipv6.conf.default.accept_ra=2
    sysctl -q net.ipv6.conf.all.accept_ra=2

    IPV6_NET=${1:-fd$(get_random_prefix)::/64}
    launch_tunslip6
    if [ "$ADVERT_ROUTE" ]; then
        launch_radvd $IPV6_NET adv_route
    else
        launch_radvd $IPV6_NET
    fi
    launch_last_process
}

run_auto()
{
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
        run_site_local
    fi
}

OPTS=$(getopt -l device:,dhcp,advert-route,shell,help -- d:Drsh "$@") || exit 1
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
        -r|--advert-route)
            ADVERT_ROUTE=1
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

check_privilege

sysctl -q net.ipv6.conf.eth0.accept_ra=2
sysctl -q net.ipv6.conf.eth0.disable_ipv6=0
[ "$LAUNCH_DHCPC" ] && launch_dhcpc

case "$1" in
    auto|"")
        run_auto
        ;;
    site_local)
        run_site_local
        ;;
    local)
        run_local
        ;;
    proxy)
        run_proxy
        ;;
    subnet)
        run_subnet $2
        ;;
    *)
        print_usage $0
        exit 1
esac
