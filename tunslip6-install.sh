#!/bin/sh
# vim: set sw=4 expandtab:
#
# Licence: GPLv2
# Created: 2020-11-18 09:27:46+01:00
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
set -e

# The script expects to run as root
[ $(id -u) == 0 ]
# If it does not exist followwing commands won't work
[ -d ./tunslip6 ]

apk add --no-cache --virtual .build-deps gcc musl-dev linux-headers make
make -C ./tunslip6 -j $(nproc) all
make -C ./tunslip6 install
make -C ./tunslip6 distclean
apk del .build-deps
