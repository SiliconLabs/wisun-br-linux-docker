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
ssh-keyscan stash.silabs.com >> ~/.ssh/known_hosts
git clone --depth=1 --quiet ssh://git@stash.silabs.com/wi-sun/wisun-br-linux.git ./wsbrd
cmake -S ./wsbrd -B ./wsbrd-build -G Ninja
ninja -C ./wsbrd-build
ninja -C ./wsbrd-build install
