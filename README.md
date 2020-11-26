WiSun Border router
===================

A WiSun Border Router (BR) allow to connect a WiSun network to internet. The
firmware WinSun BR for EFR32 is able to make most of this job. However, EFR32
only provide a Slip (Serial Line Internet Protocol) connectivity. This
repository link the Slip connection to the rest of the network.

To simplify the deployment, all the work is done inside a Docker container. It
aims to run on a Raspberry Pi, but it should work on any Linux host and even on
Windows.

The WiSun BR has to be connected to the host using USB. The docker will see it
as a serial (UART) connection.

Use of a network with IPv6 connectivity is encouraged. If IPv6 is not
available, the docker image will automatically switch to "local" mode. In local
mode, the container and the WiSun nodes are able to reach themselves, but
communication with outside is not possible. See also [Bugs and
limitations](#bugs-and-limitations).

Installation
------------

Pre-build image is not (yet) available. You have to build image yourself.

Install docker:

    sudo apt-get install docker-io

Ensure that your current user is allowed to run docker (you will have to log out
and back in for this to take effect!):

    sudo usermod -aG docker pi

Go to this repository and build the image with:

    docker build -t wisun-img .

You may to save a bit of bytes by removing the build environment and only
keeping the final image:

    docker image prune

If you have a IPv6 network, create a macvlan interface to leverage it (replace
`eth0` by the name of you physical network interface):

    docker network create -d macvlan -o parent=eth0 winsun-net

Launch image
------------

Check that the WiSun BR device is available on `/dev/ttyACM0` (or pass the
correct device name to the guest with `-s`).

Launch a shell in your image using:

    docker run -ti --privileged --network=wisun-net --name=wisun-vm wisun-img

From now, you WiSun nodes should be able to interact with your IPv6 network.

Note that the container accept a few options, you can get the list with:

    docker run -ti --privileged --rm wisun-img --help

You may want to open a shell into the container:

    docker exec -it wisun-vm sh

Bugs and limitations
--------------------

### I have no IPv6 network

This project does not aim to provide IPv6 connectivity. If your ISP does not
provide IPv6, you can either:

  - get an equipment providing IPv6 through NAT64 or 6to4
  - get an equipment advertising a site-local IPv6 prefix (eg. fd01::/64). You
    can do that using radvd with any standard Linux.

### Cannot reach (IPv4) internet from the container

This happens when you use the macvlan driver. It is necessary to get an IP from
the DHCP server of the host network. Just add `-D` when you run the docker to
run a DHCP client:

    docker run -ti --privileged --network=wisun-net wisun-br -D

### I have restarted my docker image and I can't ping my WiSun device anymore

The proxy create necessary routes when it receive a Neighbor Solicitation. Your
host has probably cached this information. The easiest way to fix that is to
flush the neighbor information of your host with:

    ip -6 neigh flush dev eth0

Alternatively you can force a neighbor discovery on your WiSun node:

    ndisc6 2a01:e35:2435:66a0:202:f7ff:fef0:0 eth0


### WiSun can reach outside network, but can't reach docker host

It is a limitation of the macvlan interface[1]. This situation is actually not
an error — it is the defined behavior of macvtap. Due to the way in which the
host's physical Ethernet is attached to the macvtap bridge, traffic into that
bridge from the guests that is forwarded to the physical interface cannot be
bounced back up to the host's IP stack. Additionally, traffic from the host's IP
stack that is sent to the physical interface cannot be bounced back up to the
macvtap bridge for forwarding to the guests.

There is several ways to workaround the problem. The easiest way probably is to
use a secondary physical network interface exclusively for the guest.

    dhcpcd --release eth1
    docker network create -d macvlan -o parent=eth1 wisun-net
    docker run -ti --privileged --network=wisun-net wisun-br


[1]: https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Virtualization_Host_Configuration_and_Guest_Installation_Guide/App_Macvtap.html

### Unable to launch the container on my Windows workstation

This project have not yet been tested on windows hosts. It seems it should work
as soon as you use  Windows Subsystem for Linux (WSL2) and the USB-UART of the
WiSun BR is handled WSL2. In other words, you should see  /dev/ttyUSB0 on your
WSL2.


Further improvements
--------------------

- tunslip6 should be able to daemonize

- replace radvd with a small RS/RA proxy. nd-proxy.c seems to mostly do the job,
  but:

   1. for an unknown reason, it does not receive RS from tun0 and do not send RA
      to tun0 (while radvd is able to do that very well)
   2. it is written in C++

