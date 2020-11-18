FROM alpine:3.12
LABEL maintainer="Jérôme Pouiller <jerome.pouiller@silabs.com>"

WORKDIR /usr/src
COPY tunslip6-install.sh .
COPY tunslip6            ./tunslip6
RUN  ./tunslip6-install.sh
