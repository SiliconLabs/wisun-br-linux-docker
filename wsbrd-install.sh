#!/bin/sh
# vim: set sw=4 expandtab:
#
# Copyright 2021, Silicon Labs
# SPDX-License-Identifier: zlib
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
set -e

# This script expects to run as root
[ $(id -u) == 0 ]
# This script will use SSH agent to authenticate to git repository
[ -n "$SSH_AUTH_SOCK" ]

apk add git openssh-client cmake ninja pkgconf linux-headers libnl3-dev libpcap-dev
mkdir -p -m 0600 ~/.ssh
ssh-keyscan github.com >> ~/.ssh/known_hosts
git clone --depth=1 --quiet --branch=v0.0.7 ssh://git@github.com/SiliconLabs/wisun-br-linux ./wsbrd
cmake -S ./wsbrd -B ./wsbrd-build -G Ninja
ninja -C ./wsbrd-build
ninja -C ./wsbrd-build install
echo -n "Built with wsbrd " >> /etc/issue
git -C ./wsbrd describe --tags --dirty --match v\* >> /etc/issue
