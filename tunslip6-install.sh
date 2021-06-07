#!/bin/sh
# vim: set sw=4 expandtab:
#
# Copyright 2021, Silicon Labs
# SPDX-License-Identifier: zlib
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
set -e

# The script expects to run as root
[ $(id -u) == 0 ]
# If it does not exist followwing commands won't work
[ -d ./tunslip6 ]

apk add linux-headers
make -C ./tunslip6 -j $(nproc) all
make -C ./tunslip6 install
