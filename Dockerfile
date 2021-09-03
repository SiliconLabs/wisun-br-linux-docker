# syntax=docker/dockerfile:1.3

FROM alpine:3.12 AS builder
LABEL maintainer="Jérôme Pouiller <jerome.pouiller@silabs.com>"
RUN apk add build-base git
RUN echo -n > /etc/issue

WORKDIR /usr/src/
COPY wsbrd-install.sh                         .
RUN --mount=type=ssh ./wsbrd-install.sh

WORKDIR /usr/src
COPY ndppd-install.sh                          .
COPY ndppd-0001-Fixes-strerror_r-GNU-XSI.patch .
COPY ndppd-0002-fix-poll-header.patch          .
RUN  ./ndppd-install.sh

WORKDIR /usr/src/
COPY openocd-install.sh                        .
RUN  ./openocd-install.sh

FROM alpine:3.12 AS runtime
ARG GIT_DESCRIBE=<unknown>
RUN mkdir -p /run/radvd
RUN apk add --no-cache radvd
RUN apk add --no-cache ndisc6
RUN apk add --no-cache libstdc++
RUN apk add --no-cache tshark
# busybox-extras contains "telnet"
RUN apk add --no-cache libusb busybox-extras
COPY --from=builder /etc/issue /etc/issue
COPY --from=builder /usr/local /usr/local
COPY init-container.sh /init
COPY firmware-winsun-rcp-0.0.4.bin /firmware-winsun-rcp.bin
COPY dhclient-hook-prefix-delegation /etc/dhcp/dhclient-exit-hooks.d/prefix_delegation
COPY wisun-device-traces /usr/bin/wisun-device-traces
# Trick: $GIT_DESCRIBE often changes, so place this line at the end to take
# advantage of the docker cache system.
RUN sed -i "1iDocker image $GIT_DESCRIBE" /etc/issue

ENTRYPOINT [ "/init" ]
CMD [ "auto" ]
