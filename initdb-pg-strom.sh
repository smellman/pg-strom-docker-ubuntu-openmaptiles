#!/bin/bash

set -e

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"

## https://github.com/openmaptiles/openmaptiles-tools/blob/master/docker/postgis/initdb-postgis.sh

# Tune-up performance for `make import-sql`
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "  Pre-configuring Postgres 14 system"
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
PGUSER="$POSTGRES_USER" "${psql[@]}" --dbname="$POSTGRES_DB" <<-'EOSQL'
    ALTER SYSTEM SET jit = 'off';
EOSQL

# Create the 'template_postgis' template db
"${psql[@]}" <<- 'EOSQL'
CREATE DATABASE template_postgis IS_TEMPLATE true;
EOSQL

# Load PostGIS into both template_database and $POSTGRES_DB
for DB in template_postgis "$POSTGRES_DB"; do
	echo "Loading extensions into $DB"
	"${psql[@]}" --dbname="$DB" <<-'EOSQL'
        -- Cleanup. Ideally parent container shouldn't pre-install those.
        DROP EXTENSION IF EXISTS postgis_tiger_geocoder;
        DROP EXTENSION IF EXISTS postgis_topology;
        CREATE EXTENSION IF NOT EXISTS pg_strom;
        CREATE EXTENSION IF NOT EXISTS postgis;
        CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
        -- Extensions needed for OpenMapTiles
        CREATE EXTENSION IF NOT EXISTS hstore;
        CREATE EXTENSION IF NOT EXISTS unaccent;
        CREATE EXTENSION IF NOT EXISTS osml10n;
        CREATE EXTENSION IF NOT EXISTS gzip;
EOSQL
done