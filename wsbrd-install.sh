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

apk add git openssh-client cmake ninja pkgconf linux-headers libnl3-dev elogind-dev cargo dbus-dev
if [ ! -d wsbrd ]; then
    git clone --depth=10 --quiet --branch=v1.3.3 https://github.com/SiliconLabs/wisun-br-linux ./wsbrd
fi
cmake -S ./wsbrd -B ./wsbrd-build -G Ninja
ninja -C ./wsbrd-build
ninja -C ./wsbrd-build install
echo -n "Built with wsbrd " >> /etc/issue
(git -C ./wsbrd describe --tags --dirty --match "*v[0-9].[0-9]*" || echo '<unknown version>') >> /etc/issue
