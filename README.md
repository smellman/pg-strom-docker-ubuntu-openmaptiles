# PG-Strom + PostGIS docker image for ubuntu

Builds for:

- ubuntu 22.04 + cuda image
- PostgreSQL 16
- PostGIS 3.5.1 from source

You need the `heterodb.license` file.
If you don't have it, let's comment out in `Dockerfile`.

## How to build

```sh
docker build -t pgstrom .
```

or without cache.

```sh
docker build --no-cache -t pgstrom .
```

## Original code

- [ytooyama pg-strom-docker](https://github.com/ytooyama/pg-strom-docker)
- [docker-library postgres](https://github.com/docker-library/postgres)
