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

apk add git cmake ninja
git clone --depth=1 --quiet --branch=v3.0.0 https://github.com/ARMmbed/mbedtls ./mbedtls
cmake -S ./mbedtls -B ./mbedtls-build -G Ninja -DENABLE_TESTING=Off
ninja -C ./mbedtls-build
ninja -C ./mbedtls-build install
