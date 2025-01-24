# PG-Strom + PostGIS + OpenMapTiles docker image for ubuntu

Builds for:

- ubuntu 22.04 + cuda image
- PostgreSQL 16
- PostGIS 3.5.2 from source

You need the `heterodb.license` file.
If you don't have it, let's comment out in `Dockerfile`.

## How to build

```sh
docker build -t smellman/pgstrom-openmaptiles .
```

or without cache (force rebuild with pg-strom master branch).

```sh
docker build --no-cache -t smellman/pgstrom-openmaptiles .
```

## How to use

edit your `docker-compose.yml` on openmaptiles:

```yaml
services:

  postgres:
    image: "smellman/pgstrom-openmaptiles:latest"
    # Use "command: postgres -c jit=off" for PostgreSQL 11+ because of slow large MVT query processing
    # Use "shm_size: 512m" if you want to prevent a possible 'No space left on device' during 'make generate-tiles-pg'
    runtime: nvidia
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu, compute, utility]
    devices:
      - /dev/infiniband:/dev/infiniband
      - /dev/nvidia0:/dev/nvidia0
      - /dev/nvidiactl:/dev/nvidiactl
      - /dev/nvidia-uvm:/dev/nvidia-uvm
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./my-postgres.conf:/etc/postgresql/postgresql.conf
    networks:
      - postgres
    ports:
      - "${PGPORT:-5432}:${PGPORT:-5432}"
    env_file: .env
    environment:
      NVIDIA_VISIBLE_DEVICES: "all"
      NVIDIA_DRIVER_CAPABILITIES: compute,utility,driver
      # postgress container uses old variable names
      POSTGRES_DB: ${PGDATABASE:-openmaptiles}
      POSTGRES_USER: ${PGUSER:-openmaptiles}
      POSTGRES_PASSWORD: ${PGPASSWORD:-openmaptiles}
      PGPORT: ${PGPORT:-5432}
```

see alse: `my-postgres.conf`

## Original code

- [ytooyama pg-strom-docker](https://github.com/ytooyama/pg-strom-docker)
- [docker-library postgres](https://github.com/docker-library/postgres)
- [smellman pg-strom-docker-ubuntu](https://github.com/smellman/pg-strom-docker-ubuntu)
