## This Dockerfile is meant to aid in the building and debugging patroni whilst developing on your local machine
## It has all the necessary components to play/debug with a single node appliance, running etcd
ARG PG_MAJOR=10
ARG PG_VERSION=10.15
ARG COMPRESS=false
ARG PGHOME=/usr/lib/postgresql/$PG_MAJOR/
ARG PGDATA=$PGHOME/data
ARG LC_ALL=C.UTF-8
ARG LANG=C.UTF-8

FROM postgres:$PG_VERSION as builder

ARG PGHOME
ARG PGDATA
ARG LC_ALL
ARG LANG

ENV ETCDVERSION=3.3.13

RUN set -ex \
    && export DEBIAN_FRONTEND=noninteractive \
    && echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend \
    && apt-get update -y \
    # postgres:10 is based on debian, which has the patroni package. We will install all required dependencies
    && apt-cache depends patroni | sed -n -e 's/.*Depends: \(python3-.\+\)$/\1/p' \
            | grep -Ev '^python3-(sphinx|etcd)' \
            | xargs apt-get install -y vim curl less jq locales sudo \
                            python3-etcd python3-kazoo python3-pip busybox \
                            net-tools iputils-ping --fix-missing \
\
    # Cleanup all locales but en_US.UTF-8
    && find /usr/share/i18n/charmaps/ -type f ! -name UTF-8.gz -delete \
    && find /usr/share/i18n/locales/ -type f ! -name en_US ! -name en_GB ! -name i18n* ! -name iso14651_t1 ! -name iso14651_t1_common ! -name 'translit_*' -delete \
    && echo 'en_US.UTF-8 UTF-8' > /usr/share/i18n/SUPPORTED \
\
    # Make sure we have a en_US.UTF-8 locale available
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
\
    # vim config
    && echo 'syntax on\nfiletype plugin indent on\nset mouse-=a\nautocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab' > /etc/vim/vimrc.local \
\
    # Prepare postgres/patroni environment
    && mkdir -p $PGHOME/.config/patroni /patroni \
    && ln -s $PGHOME/postgres.yml $PGHOME/.config/patroni/patronictl.yaml \
    && ln -s /patronictl.py /usr/local/bin/patronictl \
    && sed -i "s|/var/lib/postgresql.*|$PGHOME:/bin/bash|" /etc/passwd \
    && chown -R postgres:postgres /var/log \
\
    # Download etcd
    && curl -sL https://github.com/coreos/etcd/releases/download/v${ETCDVERSION}/etcd-v${ETCDVERSION}-linux-amd64.tar.gz \
            | tar xz -C /usr/local/bin --strip=1 --wildcards --no-anchored etcd etcdctl \
\
    # Clean up all useless packages and some files
    && apt-get purge -y --allow-remove-essential python3-pip gzip bzip2 util-linux e2fsprogs \
                libmagic1 bsdmainutils login ncurses-bin libmagic-mgc e2fslibs bsdutils \
                exim4-config gnupg-agent dirmngr libpython2.7-stdlib libpython2.7-minimal \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
        /root/.cache \
        /var/cache/debconf/* \
        /etc/rc?.d \
        /etc/systemd \
        /docker-entrypoint* \
        /sbin/pam* \
        /sbin/swap* \
        /sbin/unix* \
        /usr/local/bin/gosu \
        /usr/sbin/[acgipr]* \
        /usr/sbin/*user* \
        /usr/share/doc* \
        /usr/share/man \
        /usr/share/info \
        /usr/share/i18n/locales/translit_hangul \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/postgresql/*/man \
        /usr/share/postgresql-common/pg_wrapper \
        /usr/share/vim/vim80/doc \
        /usr/share/vim/vim80/lang \
        /usr/share/vim/vim80/tutor \
#        /var/lib/dpkg/info/* \
    && find /usr/bin -xtype l -delete \
    && find /var/log -type f -exec truncate --size 0 {} \; \
    && find /usr/lib/python3/dist-packages -name '*test*' | xargs rm -fr \
    && find /lib/x86_64-linux-gnu/security -type f ! -name pam_env.so ! -name pam_permit.so ! -name pam_unix.so -delete

# perform compression if it is necessary
ARG COMPRESS
RUN if [ "$COMPRESS" = "true" ]; then \
        set -ex \
        # Allow certain sudo commands from postgres
        && echo 'postgres ALL=(ALL) NOPASSWD: /bin/tar xpJf /a.tar.xz -C /, /bin/rm /a.tar.xz, /bin/ln -snf dash /bin/sh' >> /etc/sudoers \
        && ln -snf busybox /bin/sh \
        && files="/bin/sh /usr/bin/sudo /usr/lib/sudo/sudoers.so /lib/x86_64-linux-gnu/security/pam_*.so" \
        && libs="$(ldd $files | awk '{print $3;}' | grep '^/' | sort -u) /lib/x86_64-linux-gnu/ld-linux-x86-64.so.* /lib/x86_64-linux-gnu/libnsl.so.* /lib/x86_64-linux-gnu/libnss_compat.so.*" \
        && (echo /var/run $files $libs | tr ' ' '\n' && realpath $files $libs) | sort -u | sed 's/^\///' > /exclude \
        && find /etc/alternatives -xtype l -delete \
        && save_dirs="usr lib var bin sbin etc/ssl etc/init.d etc/alternatives etc/apt" \
        && XZ_OPT=-e9v tar -X /exclude -cpJf a.tar.xz $save_dirs \
        # we call "cat /exclude" to avoid including files from the $save_dirs that are also among
        # the exceptions listed in the /exclude, as "uniq -u" eliminates all non-unique lines.
        # By calling "cat /exclude" a second time we guarantee that there will be at least two lines
        # for each exception and therefore they will be excluded from the output passed to 'rm'.
        && /bin/busybox sh -c "(find $save_dirs -not -type d && cat /exclude /exclude && echo exclude) | sort | uniq -u | xargs /bin/busybox rm" \
        && /bin/busybox --install -s \
        && /bin/busybox sh -c "find $save_dirs -type d -depth -exec rmdir -p {} \; 2> /dev/null"; \
    fi

FROM scratch
COPY --from=builder / /

LABEL maintainer="ziminghua"

ARG PG_MAJOR
ARG COMPRESS
ARG PGHOME
ARG PGDATA
ARG LC_ALL
ARG LANG

ARG PGBIN=/usr/lib/postgresql/$PG_MAJOR/bin

ENV LC_ALL=$LC_ALL LANG=$LANG EDITOR=/usr/bin/editor
ENV PGDATA=$PGDATA PATH=$PATH:$PGBIN

COPY patroni /patroni/
COPY patroni*.py docker/entrypoint.sh /
COPY postgres.yml $PGHOME/

WORKDIR $PGHOME

RUN set -ex; \
    if ! command -v gpg > /dev/null; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            gnupg \
            dirmngr \
        ; \
        rm -rf /var/lib/apt/lists/*; \
    fi
    
# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.12
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget; \
    rm -rf /var/lib/apt/lists/*; \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    gpgconf --kill all; \
    rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    chmod +x /usr/local/bin/gosu; \
    gosu --version; \
    gosu nobody true

RUN sed -i 's/env python/&3/' /patroni*.py \
    # "fix" patroni configs
    && sed -i 's/^\(  connect_address:\|  - host\)/#&/' postgres.yml \
    && sed -i 's/^  listen: 127.0.0.1/  listen: 0.0.0.0/' postgres.yml \
    && sed -i "s|^\(  data_dir: \).*|\1$PGDATA|" postgres.yml \
    && sed -i "s|^#\(  bin_dir: \).*|\1$PGBIN|" postgres.yml \
    && sed -i 's/^  - encoding: UTF8/  - locale: en_US.UTF-8\n&/' postgres.yml \
    && sed -i 's/^\(scope\|name\|etcd\|  host\|  authentication\|  pg_hba\|  parameters\):/#&/' postgres.yml \
    && sed -i 's/^    \(replication\|superuser\|rewind\|unix_socket_directories\|\(\(  \)\{0,1\}\(username\|password\)\)\):/#&/' postgres.yml \
    && sed -i 's/^      parameters:/      pg_hba:\n      - local all all trust\n      - host replication all all md5\n      - host all all all md5\n&\n        max_connections: 1000/'  postgres.yml \
    && if [ "$COMPRESS" = "true" ]; then chmod u+s /usr/bin/sudo; fi \
    && chmod +s /bin/ping \
    && chown -R postgres:postgres $PGHOME /run

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
