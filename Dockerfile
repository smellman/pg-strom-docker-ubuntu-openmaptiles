FROM docker.io/nvidia/cuda:12.5.1-devel-ubuntu22.04 as builder

# install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN wget https://github.com/hobuinc/laz-perf/archive/refs/tags/3.4.0.tar.gz
RUN tar -xvf 3.4.0.tar.gz
RUN mkdir laz-perf-3.4.0/build
WORKDIR /src/laz-perf-3.4.0/build
RUN cmake ..
RUN make -j
RUN make install

FROM docker.io/nvidia/cuda:12.5.1-devel-ubuntu22.04

COPY --from=builder /usr/local /usr/local

# explicitly set user/group IDs
RUN set -eux; \
	groupadd -r postgres --gid=999; \
# https://salsa.debian.org/postgresql/postgresql-common/blob/997d842ee744687d99a2b2d95c1083a2615c79e8/debian/postgresql-common.postinst#L32-35
	useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres; \
# also create the postgres user's home directory with appropriate permissions
# see https://github.com/docker-library/postgres/issues/274
	install --verbose --directory --owner postgres --group postgres --mode 1777 /var/lib/postgresql

RUN set -ex; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		gnupg \
# https://www.postgresql.org/docs/16/app-psql.html#APP-PSQL-META-COMMAND-PSET-PAGER
# https://github.com/postgres/postgres/blob/REL_16_1/src/include/fe_utils/print.h#L25
# (if "less" is available, it gets used as the default pager for psql, and it only adds ~1.5MiB to our image size)
		less \
	; \
	rm -rf /var/lib/apt/lists/*

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.17
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

# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN set -eux; \
	if [ -f /etc/dpkg/dpkg.cfg.d/docker ]; then \
# if this file exists, we're likely in "debian:xxx-slim", and locales are thus being excluded so we need to remove that exclusion (since we need locales)
		grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
		sed -ri '/\/usr\/share\/locale/d' /etc/dpkg/dpkg.cfg.d/docker; \
		! grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
	fi; \
	apt-get update; apt-get install -y --no-install-recommends locales; rm -rf /var/lib/apt/lists/*; \
	echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; \
	locale-gen; \
	locale -a | grep 'en_US.utf8'
ENV LANG en_US.utf8

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libnss-wrapper \
		xz-utils \
		zstd \
	; \
	rm -rf /var/lib/apt/lists/*

RUN mkdir /docker-entrypoint-initdb.d

ENV PG_MAJOR 16
ENV PATH $PATH:/usr/lib/postgresql/$PG_MAJOR/bin
ENV POSTGIS_VERSION 3.5.2

WORKDIR /root

#Install the PostgreSQL
RUN ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
RUN apt-get update && apt-get install -y postgresql-common build-essential vim wget git gcc make clang-15 && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && apt-get install -y postgresql-$PG_MAJOR postgresql-server-dev-$PG_MAJOR postgresql-client-$PG_MAJOR

# If you want to use the full version of PG-Strom, Please Remove the Comments.
COPY heterodb.license /etc/heterodb.license
RUN wget https://heterodb.github.io/swdc/deb/heterodb-extra_5.4-1_amd64.deb && dpkg -i /root/heterodb-extra_5.4-1_amd64.deb

# Install postgis from source
RUN apt install -y libgdal-dev libprotobuf-c-dev protobuf-c-compiler
RUN wget https://download.osgeo.org/postgis/source/postgis-$POSTGIS_VERSION.tar.gz && \
    tar zxf postgis-$POSTGIS_VERSION.tar.gz && \
	cd postgis-$POSTGIS_VERSION && \
	./configure && \
	make -j && \
	make install

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
	dpkg-divert --add --rename --divert "/usr/share/postgresql/postgresql.conf.sample.dpkg" "/usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample"; \
	cp -v /usr/share/postgresql/postgresql.conf.sample.dpkg /usr/share/postgresql/postgresql.conf.sample; \
	ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$PG_MAJOR/"; \
	sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample; \
	grep -F "listen_addresses = '*'" /usr/share/postgresql/postgresql.conf.sample

RUN install --verbose --directory --owner postgres --group postgres --mode 3777 /var/run/postgresql

#Add Paths
ENV PATH /usr/local/cuda/bin:$PATH
# ENV PGDATA /var/lib/postgresql/16/main
# RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA"
ENV PGDATA /var/lib/postgresql/data
# this 1777 will be replaced by 0700 at runtime (allows semi-arbitrary "--user" values)
RUN install --verbose --directory --owner postgres --group postgres --mode 1777 "$PGDATA"
#VOLUME /var/lib/postgresql/16/main
VOLUME /var/lib/postgresql/data
#Workaround
RUN echo "PATH = '/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'" >> /etc/postgresql/$PG_MAJOR/main/environment

#Install the PG-Strom
RUN git clone https://github.com/heterodb/pg-strom && cd /root/pg-strom/src && \
    make PG_CONFIG=/usr/bin/pg_config && \
    make install PG_CONFIG=/usr/bin/pg_config

COPY docker-entrypoint.sh docker-ensure-initdb.sh /usr/local/bin/
RUN ln -sT docker-ensure-initdb.sh /usr/local/bin/docker-enforce-initdb.sh

#COPY postgresql-pg-strom.conf /etc/postgresql/16/main/postgresql.conf
#COPY postgresql-pg-strom.conf /var/lib/postgresql/16/main/postgresql.conf
#COPY postgresql-pg-strom.conf /var/lib/postgresql/data/postgresql.conf
#COPY postgresql-pg-strom.conf /usr/share/postgresql/postgresql.conf.sample
#COPY pg_hba.conf /var/lib/postgresql/16/main/pg_hba.conf
#COPY pg_hba.conf /etc/postgresql/16/main/hba.conf

RUN echo "PATH = '/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'" >> /var/lib/postgresql/$PG_MAJOR/main/environment

ENTRYPOINT ["docker-entrypoint.sh"]

# entrypoint
COPY ./initdb-pg-strom.sh /docker-entrypoint-initdb.d/11_pgstrom.sh

## COPY from https://github.com/openmaptiles/openmaptiles-tools/blob/master/docker/postgis/Dockerfile

# https://github.com/libgeos/geos/releases
#ARG GEOS_VER=3.9.3

# https://github.com/pramsey/pgsql-gzip/releases
ARG PGSQL_GZIP_TAG=v1.0.0
ARG PGSQL_GZIP_REPO=https://github.com/pramsey/pgsql-gzip.git

# https://github.com/JuliaLang/utf8proc/releases
ARG UTF8PROC_TAG=v2.5.0
ARG UTF8PROC_REPO=https://github.com/JuliaLang/utf8proc.git

# osml10n - https://github.com/openmaptiles/mapnik-german-l10n/releases
#ARG MAPNIK_GERMAN_L10N_TAG=v2.5.9.3
ARG MAPNIK_GERMAN_L10N_TAG=master
#ARG MAPNIK_GERMAN_L10N_REPO=https://github.com/openmaptiles/mapnik-german-l10n.git
ARG MAPNIK_GERMAN_L10N_REPO=https://github.com/smellman/mapnik-german-l10n.git

RUN set -eux  ;\
    apt-get -qq -y update  ;\
    ##
    ## Install build dependencies
    apt-get -qq -y --no-install-recommends install \
        build-essential \
        ca-certificates \
        # Required by Nominatim to download data files
        curl \
        git \
        pandoc \
        # $PG_MAJOR is declared in postgres docker
        postgresql-server-dev-$PG_MAJOR \
        libkakasi2-dev \
        libgdal-dev \
        clang-11 \
        llvm-11 \
    ;\
    ## Install specific GEOS version
    #cd /opt/  ;\
    #curl -o /opt/geos.tar.bz2 http://download.osgeo.org/geos/geos-${GEOS_VER}.tar.bz2  ;\
    #mkdir /opt/geos  ;\
    #tar xf /opt/geos.tar.bz2 -C /opt/geos --strip-components=1  ;\
    #cd /opt/geos/  ;\
    #./configure  ;\
    #make -j  ;\
    #make install  ;\
    #rm -rf /opt/geos*  ;\
    ##
    ## gzip extension
    cd /opt/  ;\
    git clone --quiet --depth 1 -b $PGSQL_GZIP_TAG $PGSQL_GZIP_REPO  ;\
    cd pgsql-gzip  ;\
    make  ;\
    make install  ;\
    rm -rf /opt/pgsql-gzip  ;\
    ##
    ## UTF8Proc
    cd /opt/  ;\
    git clone --quiet --depth 1 -b $UTF8PROC_TAG $UTF8PROC_REPO  ;\
    cd utf8proc  ;\
    make  ;\
    make install  ;\
    ldconfig  ;\
    rm -rf /opt/utf8proc  ;\
    ##
    ## osml10n extension (originally Mapnik German)
    cd /opt/  ;\
    git clone --quiet --depth 1 -b $MAPNIK_GERMAN_L10N_TAG $MAPNIK_GERMAN_L10N_REPO  ;\
    cd mapnik-german-l10n  ;\
    make  ;\
    make install  ;\
    rm -rf /opt/mapnik-german-l10n
    ##
	## don't cleanup for pg-strom
    # ## Cleanup
    # apt-get -qq -y --auto-remove purge \
    #     autoconf \
    #     automake \
    #     autotools-dev \
    #     build-essential \
    #     ca-certificates \
    #     bison \
    #     cmake \
    #     curl \
    #     dblatex \
    #     docbook-mathml \
    #     docbook-xsl \
    #     git \
    #     libcunit1-dev \
    #     libtool \
    #     make \
    #     g++ \
    #     gcc \
    #     pandoc \
    #     unzip \
    #     xsltproc \
    #     libpq-dev \
    #     postgresql-server-dev-$PG_MAJOR \
    #     libxml2-dev \
    #     libjson-c-dev \
    #     libgdal-dev \
    # ;\
    # rm -rf /usr/local/lib/*.a  ;\
    # rm -rf /var/lib/apt/lists/*



STOPSIGNAL SIGINT

EXPOSE 5432
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
