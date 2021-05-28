#!/bin/sh
# vim: set sw=4 expandtab:
#
# Licence: GPLv2
# Created: 2020-11-18 09:27:46+01:00
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
set -e

# This script expects to run as root
[ $(id -u) == 0 ]

apk add git libtool autoconf automake pkgconf libusb-dev
git clone --quiet -b v0.11.0 https://github.com/ntfreak/openocd.git ./openocd
git -C ./openocd submodule update --init --recursive
(cd ./openocd && ./bootstrap)
(cd ./openocd && ./configure --enable-jlink)
make -C ./openocd -j $(nproc)
make -C ./openocd install
