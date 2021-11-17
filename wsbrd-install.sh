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

apk add git openssh-client cmake ninja pkgconf linux-headers libnl3-dev elogind-dev
if [ ! -d wsbrd ]; then
    # We are going to use SSH agent to authenticate to git repository
    [ -n "$SSH_AUTH_SOCK" ]
    mkdir -p -m 0600 ~/.ssh
    ssh-keyscan github.com >> ~/.ssh/known_hosts
    git clone --depth=1 --quiet --branch=v1.0.0 ssh://git@github.com/SiliconLabs/wisun-br-linux ./wsbrd
fi
cmake -S ./wsbrd -B ./wsbrd-build -G Ninja
ninja -C ./wsbrd-build
ninja -C ./wsbrd-build install
echo -n "Built with wsbrd " >> /etc/issue
git -C ./wsbrd describe --tags --dirty --match "*v[0-9].[0-9]*" >> /etc/issue
