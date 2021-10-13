#!/bin/sh
# vim: set sw=4 expandtab:
#
# Copyright 2021, Silicon Labs
# SPDX-License-Identifier: Apache-2.0
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
# Build out-of-source else OpenOCD version will display 'x.x.x-dirty'
mkdir openocd-build
(cd ./openocd-build && ../openocd/configure --enable-jlink)
make -C ./openocd-build -j $(nproc)
make -C ./openocd-build install
