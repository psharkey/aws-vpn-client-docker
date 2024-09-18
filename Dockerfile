FROM debian:latest AS ovpn-builder

ARG DEBIAN_FRONTEND=noninteractive
ARG OPENVPN_VERSION="2.6.12"

WORKDIR /opt/openvpn

# Install dependencies and download OVPN source
RUN apt-get update \
    && apt-get install -y \
      make ca-certificates curl liblzo2-dev libpam0g-dev liblz4-dev libcap-ng-dev libnl-genl-3-dev \
      linux-libc-dev man2html libcmocka-dev python3-docutils libtool automake autoconf openssl \
      libpkcs11-helper1-dev softhsm2 gnutls-bin pkg-config patch -y \
    && curl -L -o openvpn.tar.gz "https://github.com/OpenVPN/openvpn/releases/download/v$OPENVPN_VERSION/openvpn-$OPENVPN_VERSION.tar.gz" \
    && tar xzf openvpn.tar.gz \
    && rm -rf /var/lib/apt/lists/*

# Patch and build OVPN
RUN cd "openvpn-$OPENVPN_VERSION" \
    && curl -o openvpn-aws.patch "https://raw.githubusercontent.com/botify-labs/aws-vpn-client/refs/heads/master/patches/openvpn-v$OPENVPN_VERSION-aws.patch" \
    && patch -p1 < "openvpn-aws.patch" \
    && ./configure --with-crypto-library=openssl \
    && make -j4

FROM golang:1.23.1-alpine3.20 AS server-builder

WORKDIR /opt/go-server

COPY server.go ./

# Build go server
RUN go mod init server \
    && go build

FROM debian:12-slim AS container

EXPOSE 35001/tcp

RUN apt-get update \
    && apt-get install -y \
      openssl dnsutils debconf libc6 libcap-ng0 liblz4-1 liblzo2-2 libnl-3-200 libnl-genl-3-200 \
      libpam0g libpkcs11-helper1 libssl3 libsystemd0 easy-rsa openvpn-dco-dkms \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/vpn

COPY --from=ovpn-builder /opt/openvpn/openvpn-2.6.12/src/openvpn/openvpn ./openvpn-bin
COPY --from=server-builder /opt/go-server/server ./go_server
COPY entrypoint.sh /opt/vpn/entrypoint.sh

ENTRYPOINT ["/opt/vpn/entrypoint.sh"]