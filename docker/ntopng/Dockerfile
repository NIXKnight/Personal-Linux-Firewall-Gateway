FROM debian:bullseye-slim

ARG DEBIAN_FRONTEND=noninteractive

ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN set -eux; \
    apt-get update; \
    apt-get -y dist-upgrade; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
    apt-get -y install --no-install-recommends wget lsb-release gnupg apt-transport-https ca-certificates; \
    wget https://packages.ntop.org/apt-stable/bullseye/all/apt-ntop-stable.deb; \
    dpkg --install apt-ntop-stable.deb; \
    apt-get update; \
    apt-get -y install --no-install-recommends ntopng ntopng-data ndpi pfring ntop-license; \
    apt-get remove -y wget apt-transport-https gnupg; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean all; \
    rm -rf /var/lib/apt/lists/*

VOLUME [ "/var/lib/ntopng" ]

COPY run.sh /run.sh

ENTRYPOINT [ "/run.sh" ]
