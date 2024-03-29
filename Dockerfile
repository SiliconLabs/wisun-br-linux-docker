# syntax=docker/dockerfile:1.3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021, Silicon Labs

FROM alpine:3.12 AS builder
LABEL maintainer="Jérôme Pouiller <jerome.pouiller@silabs.com>"
RUN apk add build-base git
RUN git config --global advice.detachedHead false
RUN echo -n > /etc/issue

WORKDIR /usr/src/
COPY openocd-install.sh                        .
RUN  ./openocd-install.sh

# The developement release of wsbrd depends on external mbedtls
WORKDIR /usr/src/
COPY mbedtls-install.sh                        .
RUN  ./mbedtls-install.sh

WORKDIR /usr/src/
# The [x] allow to change wisun-br-linux into a pattern, so Docker won't
# complain if does not exist
COPY wisun-br-linu[x]                         wsbrd
COPY wsbrd-install.sh                         .
RUN ./wsbrd-install.sh

FROM alpine:3.12 AS runtime
RUN mkdir -p /run/radvd
RUN mkdir -p /var/lib/wsbrd
RUN apk add --no-cache libnl3 libelogind
RUN apk add --no-cache elogind
RUN apk add --no-cache radvd
RUN apk add --no-cache ndisc6
RUN apk add --no-cache libstdc++
RUN apk add --no-cache dhclient
# busybox-extras contains "telnet"
RUN apk add --no-cache libusb busybox-extras
COPY --from=builder /etc/issue /etc/issue
COPY --from=builder /etc/dbus-1/system.d /etc/dbus-1/system.d
COPY --from=builder /usr/local /usr/local
COPY init-container.sh /init
COPY wsbrd.conf /etc/wsbrd.conf
COPY firmware-winsun-rcp-1.2.0.s37 /firmware-winsun-rcp.s37
COPY dhclient-hook-prefix-delegation /etc/dhclient-exit-hooks.d/prefix_delegation
COPY wisun-device-traces /usr/bin/wisun-device-traces
# Trick: $GIT_DESCRIBE often changes, so place this line at the end to take
# advantage of the docker cache system.
ARG GIT_DESCRIBE=<unknown>
RUN sed -i "1iDocker image $GIT_DESCRIBE" /etc/issue

ENTRYPOINT [ "/init" ]
CMD [ "auto" ]
