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

apk add git glib-dev
git clone --quiet https://github.com/DanielAdolfsson/ndppd.git ./ndppd
git -C ./ndppd reset --hard e01d67a
git -C ./ndppd apply ../ndppd-0001-Fixes-strerror_r-GNU-XSI.patch
git -C ./ndppd apply ../ndppd-0002-fix-poll-header.patch
make -C ./ndppd -j $(nproc)
make -C ./ndppd install
