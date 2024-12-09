FROM debian:bookworm-slim AS build
LABEL maintainer="Tomáš Müller<tomas.muller@img.cas.cz>"

ARG GIT_REPO=https://github.com/rdkit/rdkit.git
ARG GIT_BRANCH=master
# also change the BOOST_VER variable in the other sections
ARG BOOST_VER=1.81
ARG POSTGRES_VER=15

RUN apt update &&\
  apt install -y --no-install-recommends \
  build-essential\
  cmake\
  libboost-system$BOOST_VER*\
  libboost-thread$BOOST_VER*\
  libboost-serialization$BOOST_VER*\
  libboost-python$BOOST_VER*\
  libboost-regex$BOOST_VER*\
  libboost-chrono$BOOST_VER*\
  libboost-date-time$BOOST_VER*\
  libboost-atomic$BOOST_VER*\
  libboost-iostreams$BOOST_VER*\
  libboost-program-options$BOOST_VER*\
  libeigen3-dev\
  zlib1g-dev\
  git\
  wget\
  zip\
  unzip\
  libfreetype6-dev \
  curl \
  ca-certificates && \
  install -d /usr/share/postgresql-common/pgdg && \
  curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
  sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
  apt update && \
  apt install -y --no-install-recommends \
  postgresql-${POSTGRES_VER} \
  postgresql-server-dev-${POSTGRES_VER}


ARG GIT_TAG
RUN if [ $GIT_TAG ]; then echo "Checking out tag $GIT_TAG from repo $GIT_REPO branch $GIT_BRANCH"; else echo "Checking out repo $GIT_REPO branch $GIT_BRANCH"; fi
RUN git clone -b $GIT_BRANCH --single-branch $GIT_REPO &&\
  if [ $GIT_TAG ]; then cd rdkit && git fetch --tags && git checkout $GIT_TAG; fi

ENV RDBASE=/rdkit
ENV LD_LIBRARY_PATH=$RDBASE/lib:/usr/lib/x86_64-linux-gnu:/usr/lib/aarch64-linux-gnu/
RUN mkdir $RDBASE/build
WORKDIR $RDBASE/build

RUN cmake -Wno-dev\
  -DRDK_INSTALL_INTREE=OFF\
  -DRDK_BUILD_INCHI_SUPPORT=ON\
  -DRDK_BUILD_AVALON_SUPPORT=ON\
  -DRDK_BUILD_PYTHON_WRAPPERS=OFF\
  -DRDK_BUILD_SWIG_WRAPPERS=OFF\
  -DRDK_BUILD_PGSQL=ON\
  -DPostgreSQL_ROOT=/usr/lib/postgresql/${POSTGRES_VER} \
  -DPostgreSQL_TYPE_INCLUDE_DIR=/usr/include/postgresql/${POSTGRES_VER}/server\
  -DCMAKE_INSTALL_PREFIX=/usr\
  -DCPACK_PACKAGE_RELOCATABLE=OFF\
  ..


RUN nproc=$(getconf _NPROCESSORS_ONLN)\
  && make -j $(( nproc > 2 ? nproc - 2 : 1 ))
RUN make install


FROM debian:bookworm-slim

ARG BOOST_VER=1.81
ARG POSTGRES_VER=15

RUN apt update &&\
  apt install -y --no-install-recommends \
  libboost-system$BOOST_VER.0\
  libboost-thread$BOOST_VER.0\
  libboost-serialization$BOOST_VER.0\
  libboost-python$BOOST_VER.0\
  libboost-regex$BOOST_VER.0\
  libboost-chrono$BOOST_VER.0\
  libboost-date-time$BOOST_VER.0\
  libboost-atomic$BOOST_VER.0\
  libboost-iostreams$BOOST_VER.0\
  libboost-program-options$BOOST_VER.0\
  libeigen3-dev\
  zlib1g-dev\
  wget\
  zip\
  unzip\
  libfreetype6-dev \
  gosu \
  curl \
  ca-certificates && \
  install -d /usr/share/postgresql-common/pgdg && \
  curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
  sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
  apt update && \
  apt install -y --no-install-recommends \
  postgresql-${POSTGRES_VER}

ENV RDBASE=/rdkit
RUN mkdir -p $RDBASE/build/Code/PgSQL/rdkit/ && mkdir -p $RDBASE/Code/PgSQL/rdkit/
COPY --from=build $RDBASE/build/Code/PgSQL/rdkit/ $RDBASE/build/Code/PgSQL/rdkit/
COPY --from=build $RDBASE/Code/PgSQL/rdkit/rdkit.control $RDBASE/Code/PgSQL/rdkit/
RUN sh $RDBASE/build/Code/PgSQL/rdkit/pgsql_install.sh


ENV PGDATA=/var/lib/postgresql/data
ENV PATH=$PATH:/usr/lib/postgresql/$POSTGRES_VER/bin
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA"

VOLUME /var/lib/postgresql/data

COPY docker-entrypoint.sh docker-ensure-initdb.sh /usr/local/bin/
RUN ln -sT docker-ensure-initdb.sh /usr/local/bin/docker-enforce-initdb.sh
ENV PATH=$PATH:/usr/lib/postgresql/${POSTGRES_VER}/bin/
RUN mkdir /docker-entrypoint-initdb.d
EXPOSE 5432
STOPSIGNAL SIGINT

# make the sample config easier to munge (and "correct by default")
RUN mv -v "/usr/share/postgresql/$POSTGRES_VER/postgresql.conf.sample" /usr/share/postgresql/ \
  && ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$POSTGRES_VER/" \
  && sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

RUN apt-get clean -y

WORKDIR /

ENV POSTGRES_INITDB_ARGS='--encoding=UTF-8 --lc-collate=C --lc-ctype=C'

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["postgres"]