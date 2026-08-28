# Overview

This document lists of all environment variables read by Vroom cluster
components and describes their purpose.


# Environment Variables

- `VRM_POD_IP` - when set it must contain a valid IPv4 or IPv6 address. The
    address is used to advertise the service in etcd.
- `VRM_LOG_LEVEL` - when set it overrides the default log level (INFO) and must
    be one of the following severity levels: DEBUG, INFO, WARN, ERROR, or FATAL.
- `VRM_LICENSE` - (required) must be filled with a valid json-format VRM 
    license (use sample licenses under `ROOT/data/licenses` for testing).
- `VRM_STORAGE_GROUPS` - When set, cluster will be constructed to use storage
    groups according to the configuration it gave.
- `VRM_OTEL_ENDPOINT` - when set, telemetry data will be pushed to the specified 
    endpoint using OTLP via gRPC (format: "hostname:port").
- `VRM_WORKING_DIR` - configures the working directory for different services. 
    In specific case of storage service, when multiple working directories are 
    desired, they can be listed and separated by ":".
- `VRM_TRACES_ENABLED` - when set to `1`, Vroom will generate traces and send 
    them to the configured OTEL collector.
- `VRM_NO_DEDUPE` - in entrypoint, do not send data through deduplicator but 
    write directly to storage instead.

# Backend Connection

> **NOTE:** These are ignored when a valid test license is provided through
        `VRM_LICENSE`.

- `VRM_BACKEND_HOST` - configure host of the backend service. Please fill domain name only like this: 'backend.vroom.io'.
- `VRM_CUSTOMER_ID` - configure customer ID for the backend service.
- `VRM_ACCESS_TOKEN` - configure access token for the backend service.

# Database Connection

- `VRM_DB_HOSTPORT` - configure host and port of the DBMS 
    (format: "hostname:port").
- `VRM_DB_DIRECTORY_CONNECTIONS` - number of connections used to connect to 
    directory database.
- `VRM_DB_MULTIPART_CONNECTIONS` - number of connections used to connect to 
    multipart database.
- `VRM_DB_USER` - configure user name for connections to the DBMS.
- `VRM_DB_PASS` - pass the connection password for the user given in `VRM_DB_USER`.

# ETCD Authentication

- `VRM_ETCD_USERNAME` - username for etcd authentication.
- `VRM_ETCD_PASSWORD` - password for etcd authentication.
