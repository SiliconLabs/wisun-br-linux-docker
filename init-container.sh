#!/bin/sh
# vim: set sw=4 expandtab:
#
# Copyright 2021, Silicon Labs
# SPDX-License-Identifier: zlib
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
set +m

WSBRD_PID=-1
UART=/dev/ttyACM0

die()
{
    echo "$@" >&2
    exit 1
}

print_usage()
{
    cat << EOF >&2
Usage: $1 [OPTIONS] [WISUN_PARAMS] [MODE]

Setup the docker container to create a Wi-SUN Border Router.

Container options:
  -u, --uart=DEVICE   UART device to use (default: /dev/ttyACM0).
  -D, --dhcp          Configure IPv4 using DHCP. Use it if you rely on a
                      network interface with macvlan driver.
  -r, --advert-route  Advertise the new route on eth0. Only works with the subnet
                      mode. Most of the hosts won't accept le route unless the
                      parameter accept_ra_rt_info_max_plen is at least the size
                      of the advertised prefix size. You may use it if the
                      router of your network is not able to manage the new route
                      itself.
  -F, --flash=FW_PATH Flash radio board with FW_PATH. If FW_PATH is "-", flash
                      built-in firmware which should work with most of the
                      boards.
  -T, --chip-traces   Show traces from the chip.
  -s, --shell         Launch a shell on startup.
  -h, --help          Show this help.

Modes:
  local           The nodes will be only able to communicate with the docker
                  instance using a random site-local prefix.
  site_local      Advertise a random site-local prefix and run a proxy. Local
                  workstations will retrieve an IPv6 address allowing them to
                  communicate with Wi-SUN nodes.
  proxy           Re-use the local IPv6 prefix to configure Wi-SUN nodes.
  subnet [PREFIX] Use PREFIX to configure Wi-SUN nodes. PREFIX should come from
                  configuration of the parent router. If PREFIX is 'dhcp', get
                  prefix using DHCPv6-PD (experimental). If PREFIX is not
                  defined, generate a random site-local one.
  auto            Detect if a local IPv6 network is available and launch
                  \`site_local' or \`proxy' accordingly.

Note that random site-local prefixes are not routable (ie. you can't access
outside with these).

Wi-SUN parameters:
  -n, --ws-network=NAME    Set Wi-SUN network name (default: Wi-SUN)
  -d, --ws-domain=COUNTRY  Set Wi-SUN regulatory domain. Valid values: WW, EU,
                           NA (default), JP...
  -m, --ws-mode=VAL        Set operating mode. Valid values: 1a, 1b (default),
                           2a, 2b, 3, 4a, 4b and 5
  -c, --ws-class=VAL       Set operating class. Valid values: 1 (default), 2, 3
                           or 4
  -S, --ws-size=SIZE       Optimize network timings considering the number of
                           expected nodes on the network. Valid values: CERT
                           (development and certification), S (< 100, default),
                           M (100-800), L (800-2500), XL (> 2500)
  -K, --ws-key=FILE        Private key (default: br_key.pem)
  -C, --ws-cert=FILE       Certificate for the key (default: br_cert.pem)
  -A, --ws-authority=FILE  Certificate of the authority (CA) (default:
                           ca_cert.pem)

By default, this container uses embedded test certficates (located in
/usr/local/share/wsbrd/examples/). If you provide your owns, don't forget to map
the files into the container (passing option -v to \`docker run').

Examples:

  Provide minimal infrastructure to configure Wi-SUN device through a Border
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
    # This could improved, but we use dhcpc to get address and dhclient to get
    # prefix delegation
    umount /etc/resolv.conf
    udhcpc -i eth0
}

launch_dhclient()
{
    # This could improved, but we use dhcpc to get address and dhclient to get
    # prefix delegation
    dhclient -P eth0
}

launch_wsbrd()
{
    IPV6_NET=$1
    [ -e "$UART" ] || die "Failed to detect $UART"

    echo " ---> [1mLaunch wsbrd[0m"
    echo "Command line:"
    echo "    wsbrd -u $UART -F /etc/wsbrd.conf$WSBRD_ARGS -o ipv6_prefix=$IPV6_NET --network=\"$WS_NETWORK\""
    wsbrd -u $UART -F /etc/wsbrd.conf$WSBRD_ARGS -o ipv6_prefix=$IPV6_NET --network="$WS_NETWORK" &
    WSBRD_PID=$!

    # We expect that accept_ra=2 and radvd is running on tun0
    for i in $(seq 10); do
        ip -6 addr show scope global | grep -q tun0 && break
        sleep 0.2
    done
}

generate_radvd_conf()
{
    IPV6_NET=$1
    EXT_BEHAVIOR=$2

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
}

launch_radvd()
{
    IPV6_NET=$1
    EXT_BEHAVIOR=$2

    echo " ---> [1mLaunch radvd on $IPV6_NET[0m"
    generate_radvd_conf $IPV6_NET $EXT_BEHAVIOR
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
        if tty > /dev/nul 2> /dev/null; then
            set -m
        else
            echo "Cannot get tty (missing -t in docker command line?)"
        fi
        echo " ---> [1mLaunch sh[0m"
        exec sh
    elif [ "$LAUNCH_TRACES" ]; then
        echo " ---> [1mLaunch wisun-device-traces[0m"
        exec wisun-device-traces
    else
        wait $WSBRD_PID
        echo " ---> [1mWi-SUN border router has disappeared[0m"
    fi
}

flash_firmware()
{
    IS_MANDATORY=$1
    cat << 'EOF' > /tmp/openocd-rtt.cfg
rtt setup 0x20001c00 0x04000 "SEGGER RTT"
rtt server start 1001 0
telnet_port 1002
gdb_port 1003
tcl_port 1004
init
rtt start
EOF
    echo " ---> [1mLaunch OpenOCD[0m"
    openocd -d0 -f board/efm32.cfg -f /tmp/openocd-rtt.cfg &
    OPENOCD_PID=$!
    sleep 1
    [ -d /proc/$OPENOCD_PID ] || die "Cannot connect to JLink probe"
    [ -e "$FIRMWARE" ] || die "'$FIRMWARE' not found (missing -v in docker command?)"
    echo "run \"program $FIRMWARE 0 reset\" on JLink probe"
    echo "program $FIRMWARE 0 reset" | nc 127.0.0.1 1002 > /dev/null
    kill $OPENOCD_PID
    echo "You may have to hard-reset the board if it hangs"
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
        ip -6 addr show scope global | grep -q eth0 && break
        sleep 0.2
    done
    IPV6_NET=$(rdisc6 -r 10 -w 400 -q -1 eth0)
    [ "$IPV6_NET" ] || die "Failed to get IPv6 address"

    launch_wsbrd $IPV6_NET
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
    launch_radvd fd$SITE_PREFIX::/64 adv_prefix
    launch_wsbrd fd$SITE_PREFIX::/64
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
    launch_wsbrd fd$SITE_PREFIX::/64
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
    if [ "$ADVERT_ROUTE" ]; then
        launch_radvd $IPV6_NET adv_route
    fi
    launch_wsbrd $IPV6_NET
    launch_last_process
}

run_dhcpv6pd()
{
    sysctl -q net.ipv6.conf.default.disable_ipv6=0
    sysctl -q net.ipv6.conf.all.disable_ipv6=0
    sysctl -q net.ipv6.conf.default.forwarding=1
    sysctl -q net.ipv6.conf.all.forwarding=1
    sysctl -q net.ipv6.conf.default.accept_ra=2
    sysctl -q net.ipv6.conf.all.accept_ra=2

    launch_tunslip6
    # dhclient will start radvd as soon as it will receive a DHCPv6-PD reply.
    if [ "$ADVERT_ROUTE" ]; then
        generate_radvd_conf bad:beef adv_route
    fi
    launch_dhclient
    launch_last_process
}

run_auto()
{
    HAVE_IPV6=
    printf "Probe network"
    for i in $(seq 20); do
        ip -6 addr show scope global | grep -q eth0 && HAVE_IPV6=1 && break
        printf "."
        sleep 0.2
    done
    printf "\n"
    if [ "$HAVE_IPV6" ]; then
        echo " ---> [1mFound IPv6 network[0m"
        run_proxy
    else
        echo " ---> [1mNo network found[0m"
        run_site_local
    fi
}

cat /etc/issue

WS_NETWORK="Wi-SUN"
OPTS=$(getopt -l shell,chip-traces,dhcp,device:,uart:,advert-route,flash:,ws-network:,ws-domain:,ws-mode:,ws-class:,ws-size:,ws-key:,ws-cert:,ws-authority:,help -- sTDu:rF:n:d:m:c:S:K:C:A:h "$@") || exit 1
eval set -- "$OPTS"
while true; do
    case "$1" in
        -s|--shell)
            LAUNCH_SHELL=1
            shift 1
            ;;
        -T|--chip-traces)
            LAUNCH_TRACES=1
            shift 1
            ;;
        -D|--dhcp)
            LAUNCH_DHCPC=1
            shift 1
            ;;
        -u|--uart|--device)
            UART=$2
            shift 2
            ;;
        -r|--advert-route)
            ADVERT_ROUTE=1
            shift 2
            ;;
        -F|--flash)
            if [ -z "$2" -o "$2" == "-" ]; then
                FIRMWARE=/firmware-winsun-rcp.bin
            else
                FIRMWARE=$2
            fi
            shift 2
            ;;
        -n|--ws-network)
            WS_NETWORK="$2"
            shift 2
            ;;
        -d|--ws-domain)
            WSBRD_ARGS="$WSBRD_ARGS -o domain=$2"
            shift 2
            ;;
        -m|--ws-mode)
            WSBRD_ARGS="$WSBRD_ARGS -o mode=$2"
            shift 2
            ;;
        -c|--ws-class)
            WSBRD_ARGS="$WSBRD_ARGS -o class=$2"
            shift 2
            ;;
        -S|--ws-size)
            WSBRD_ARGS="$WSBRD_ARGS -o size=$2"
            shift 2
            ;;
        -K|--ws-key)
            WSBRD_ARGS="$WSBRD_ARGS -o key='$2'"
            shift 2
            ;;
        -C|--ws-cert)
            WSBRD_ARGS="$WSBRD_ARGS -o certificate='$2'"
            shift 2
            ;;
        -A|--ws-authority)
            WSBRD_ARGS="$WSBRD_ARGS -o authority='$2'"
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
[ "$LAUNCH_SHELL" -a "$LAUNCH_TRACES" ] && die "--shell and --chip-traces are exclusive"

check_privilege

sysctl -q net.ipv6.conf.eth0.accept_ra=2
sysctl -q net.ipv6.conf.eth0.disable_ipv6=0
[ "$LAUNCH_DHCPC" ] && launch_dhcpc
[ "$FIRMWARE" ] && flash_firmware

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
        if [ "$2" = dhcp -o "$2" = DHCP ]; then
            run_dhcpv6pd
        else
            run_subnet $2
        fi
        ;;
    *)
        print_usage $0
        exit 1
esac
