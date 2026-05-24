#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLUSTER_DIR=".cluster"
COMPOSE_FILE="$CLUSTER_DIR/docker-compose.deps.yaml"
STATE_FILE="$CLUSTER_DIR/state"
CONFIG_FILE="$CLUSTER_DIR/config"
LOGS_DIR="$CLUSTER_DIR/logs"
DATA_DIR="$CLUSTER_DIR/data"

DEFAULT_ROOT_USER="main"
DEFAULT_ROOT_ACCESS_KEY="0555b35654ad1656d804"
DEFAULT_ROOT_SECRET_KEY="h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q=="
DEFAULT_STORAGE_GROUPS='[{"id":0,"type":"ROUND_ROBIN","storages":1}]'
DB_PORT=5432
ETCD_PORT=2379

usage() {
    cat >&2 <<'EOF'
Usage: cluster.sh <action> [options]

Actions:
  start   Create .cluster/ and start the cluster
  stop    Stop the cluster, keep .cluster/
  delete  Stop and remove .cluster/

Start options:
  --native              Run UH services as native host processes (default)
  --docker              Run UH services in Docker containers
  --bin-dir PATH        Binary directory with uh-cluster, uh-access (required)
  --storage-groups JSON Storage groups JSON (default: ROUND_ROBIN, 1 storage)

Root user (env vars, defaults match s3tests.conf):
  UH_ROOT_USER, UH_ROOT_ACCESS_KEY, UH_ROOT_SECRET_KEY
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

check_prerequisites() {
    local missing=()
    for cmd in docker jq curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "missing required commands: ${missing[*]}"
}

compose_project() {
    echo "uhcluster-$(echo -n "$(pwd)" | md5sum | cut -c1-8)"
}

wait_for_http() {
    local url="$1" timeout="${2:-60}"
    for ((t = 0; t < timeout; t++)); do
        curl -so /dev/null "$url" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

generate_deps_compose() {
    cat > "$COMPOSE_FILE" <<YAML
services:
  db:
    image: postgres:17.9
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: uh
    ports:
      - "${DB_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 10

  db-init:
    build:
      context: ${REPO_ROOT}
      dockerfile: docker/Dockerfile.db-init
    network_mode: host
    depends_on:
      db:
        condition: service_healthy
    environment:
      DB_USER: postgres
      DB_HOST: localhost
      DB_PORT: ${DB_PORT}
      PGPASSWORD: uh
    restart: "no"

  etcd:
    image: quay.io/coreos/etcd:v3.5.12
    command:
      - etcd
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://localhost:${ETCD_PORT}
    ports:
      - "${ETCD_PORT}:2379"
YAML
}

do_start() {
    local mode="native" bin_dir="" storage_groups="$DEFAULT_STORAGE_GROUPS"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --native)         mode="native"; shift ;;
            --docker)         mode="docker"; shift ;;
            --bin-dir)        bin_dir="$2"; shift 2 ;;
            --storage-groups) storage_groups="$2"; shift 2 ;;
            *)                die "unknown option: $1" ;;
        esac
    done

    [[ -n "$bin_dir" ]] || die "--bin-dir is required"
    [[ -d "$bin_dir" ]] || die "bin-dir does not exist: $bin_dir"
    bin_dir="$(cd "$bin_dir" && pwd)"

    [[ -e "$CLUSTER_DIR" ]] && die ".cluster/ already exists — run 'stop' or 'delete' first"

    local root_user="${UH_ROOT_USER:-$DEFAULT_ROOT_USER}"
    local root_access_key="${UH_ROOT_ACCESS_KEY:-$DEFAULT_ROOT_ACCESS_KEY}"
    local root_secret_key="${UH_ROOT_SECRET_KEY:-$DEFAULT_ROOT_SECRET_KEY}"
    local project
    project="$(compose_project)"
    local uh_license
    uh_license="$(<"$REPO_ROOT/data/licenses/UltiHash-Test-1PB.lic")"

    echo "Starting cluster (mode: $mode, project: $project)"

    mkdir -p "$LOGS_DIR" "$DATA_DIR"

    jq -n \
        --arg mode "$mode" \
        --arg bin_dir "$bin_dir" \
        --arg root_user "$root_user" \
        --arg root_access_key "$root_access_key" \
        --arg root_secret_key "$root_secret_key" \
        --argjson storage_groups "$storage_groups" \
        '{mode: $mode, bin_dir: $bin_dir, root_user: $root_user,
          root_access_key: $root_access_key, root_secret_key: $root_secret_key,
          storage_groups: $storage_groups}' > "$CONFIG_FILE"

    cp "$REPO_ROOT/docker/policies.json" "$CLUSTER_DIR/policies.json"
    generate_deps_compose

    echo "Starting dependencies (postgres, etcd)..."
    docker compose -f "$COMPOSE_FILE" -p "$project" up -d

    echo "Waiting for database initialization..."
    docker compose -f "$COMPOSE_FILE" -p "$project" wait db-init

    echo "Starting UH services..."
    if [[ "$mode" == "native" ]]; then
        _start_native "$bin_dir" "$storage_groups" "$uh_license" "$project" \
            "$root_user" "$root_access_key" "$root_secret_key"
    else
        _start_docker "$bin_dir" "$storage_groups" "$uh_license" "$project" \
            "$root_user" "$root_access_key" "$root_secret_key"
    fi

    echo "Waiting for cluster to become available..."
    if ! wait_for_http "http://localhost:8080" 60; then
        echo "error: cluster did not become ready in 60s" >&2
        do_stop || true
        exit 1
    fi

    echo "Cluster is ready at http://localhost:8080"
}

_start_native() {
    local bin_dir="$1" storage_groups="$2" uh_license="$3" project="$4"
    local root_user="$5" root_access_key="$6" root_secret_key="$7"
    local registry="http://localhost:$ETCD_PORT"
    local cluster_abs
    cluster_abs="$(cd "$CLUSTER_DIR" && pwd)"

    echo "Initializing root user..."
    UH_DB_HOSTPORT="localhost:$DB_PORT" UH_DB_USER=postgres UH_DB_PASS=uh \
        "$bin_dir/uh-access" user-add --superuser --if-not-exists "$root_user" 'root:::'
    UH_DB_HOSTPORT="localhost:$DB_PORT" UH_DB_USER=postgres UH_DB_PASS=uh \
        "$bin_dir/uh-access" key-add "$root_user" "$root_access_key" "$root_secret_key" 2000000000

    export UH_LOG_LEVEL=DEBUG
    export UH_LICENSE="$uh_license"
    export UH_DB_HOSTPORT="localhost:$DB_PORT"
    export UH_DB_USER=postgres
    export UH_DB_PASS=uh
    export UH_STORAGE_GROUPS="$storage_groups"

    declare -A pids

    mkdir -p "$cluster_abs/data/coordinator"
    "$bin_dir/uh-cluster" --registry "$registry" coordinator \
        >> "$cluster_abs/logs/coordinator.log" 2>&1 &
    pids[coordinator]=$!

    while IFS= read -r group; do
        local gid num_s
        gid="$(jq -r '.id' <<< "$group")"
        num_s="$(jq -r '.storages' <<< "$group")"
        for ((i = 0; i < num_s; i++)); do
            local sname="storage-${gid}-${i}"
            local port=$((9311 + gid * 100 + i))
            mkdir -p "$cluster_abs/data/$sname"
            UH_STORAGE_GROUP_ID="$gid" UH_STORAGE_INSTANCE_ID="$i" \
                "$bin_dir/uh-cluster" --registry "$registry" \
                    --workdir "$cluster_abs/data/$sname" storage --port "$port" \
                    >> "$cluster_abs/logs/${sname}.log" 2>&1 &
            pids[$sname]=$!
        done
    done < <(jq -c '.[]' <<< "$storage_groups")

    "$bin_dir/uh-cluster" --registry "$registry" entrypoint \
        >> "$cluster_abs/logs/entrypoint.log" 2>&1 &
    pids[entrypoint]=$!

    local pids_json="{}"
    for name in "${!pids[@]}"; do
        pids_json="$(jq --arg k "$name" --argjson v "${pids[$name]}" '. + {($k): $v}' <<< "$pids_json")"
    done

    jq -n \
        --arg status "running" \
        --arg mode "native" \
        --arg project "$project" \
        --argjson pids "$pids_json" \
        '{status: $status, mode: $mode, project: $project, pids: $pids, containers: null}' \
        > "$STATE_FILE"
}

_start_docker() {
    local bin_dir="$1" storage_groups="$2" uh_license="$3" project="$4"
    local root_user="$5" root_access_key="$6" root_secret_key="$7"
    local registry="http://localhost:$ETCD_PORT"
    local cluster_abs
    cluster_abs="$(cd "$CLUSTER_DIR" && pwd)"
    local image_tag="uh-cluster-test:${project}"

    echo "Building cluster image from $bin_dir..."
    docker build \
        --build-arg "BIN_PATH=${bin_dir#"$REPO_ROOT/"}" \
        -t "$image_tag" \
        -f "$REPO_ROOT/docker/Dockerfile.cluster" \
        "$REPO_ROOT"

    echo "Initializing root user..."
    docker run --rm \
        --network host \
        -e "UH_DB_HOSTPORT=localhost:$DB_PORT" \
        -e UH_DB_USER=postgres \
        -e UH_DB_PASS=uh \
        "$image_tag" \
        /usr/local/bin/uh-access user-add --superuser --if-not-exists "$root_user" 'root:::'
    docker run --rm \
        --network host \
        -e "UH_DB_HOSTPORT=localhost:$DB_PORT" \
        -e UH_DB_USER=postgres \
        -e UH_DB_PASS=uh \
        "$image_tag" \
        /usr/local/bin/uh-access key-add "$root_user" "$root_access_key" "$root_secret_key" 2000000000

    # Write env file to avoid shell quoting issues with JSON values
    local env_file="$cluster_abs/cluster.env"
    printf 'UH_LOG_LEVEL=DEBUG\nUH_LICENSE=%s\nUH_DB_HOSTPORT=localhost:%s\nUH_DB_USER=postgres\nUH_DB_PASS=uh\nUH_STORAGE_GROUPS=%s\n' \
        "$uh_license" "$DB_PORT" "$storage_groups" > "$env_file"

    local containers=()

    _run_service() {
        local name="$1" cmd="$2"; shift 2
        mkdir -p "$cluster_abs/data/$name"
        docker run -d \
            --network host \
            --name "${project}-${name}" \
            --user root \
            --env-file "$env_file" \
            -v "$cluster_abs/data/$name:/var/lib/uh" \
            -v "$cluster_abs/logs:/cluster-logs" \
            "$@" \
            "$image_tag" \
            sh -c "$cmd >> /cluster-logs/${name}.log 2>&1"
        containers+=("${project}-${name}")
    }

    _run_service "coordinator" \
        "/usr/local/bin/uh-cluster --registry $registry coordinator"

    while IFS= read -r group; do
        local gid num_s
        gid="$(jq -r '.id' <<< "$group")"
        num_s="$(jq -r '.storages' <<< "$group")"
        for ((i = 0; i < num_s; i++)); do
            local sname="storage-${gid}-${i}"
            _run_service "$sname" \
                "/usr/local/bin/uh-cluster --registry $registry storage" \
                -e "UH_STORAGE_GROUP_ID=$gid" \
                -e "UH_STORAGE_INSTANCE_ID=$i"
        done
    done < <(jq -c '.[]' <<< "$storage_groups")

    # Entrypoint gets an additional policy file mount
    mkdir -p "$cluster_abs/data/entrypoint"
    docker run -d \
        --network host \
        --name "${project}-entrypoint" \
        --user root \
        --env-file "$env_file" \
        -v "$cluster_abs/data/entrypoint:/var/lib/uh" \
        -v "$cluster_abs/logs:/cluster-logs" \
        -v "$cluster_abs/policies.json:/etc/uh/policies.json:ro" \
        "$image_tag" \
        sh -c "/usr/local/bin/uh-cluster --registry $registry entrypoint >> /cluster-logs/entrypoint.log 2>&1"
    containers+=("${project}-entrypoint")

    local containers_json
    containers_json="$(printf '%s\n' "${containers[@]}" | jq -R . | jq -s .)"

    jq -n \
        --arg status "running" \
        --arg mode "docker" \
        --arg project "$project" \
        --arg image "$image_tag" \
        --argjson containers "$containers_json" \
        '{status: $status, mode: $mode, project: $project,
          image: $image, pids: null, containers: $containers}' \
        > "$STATE_FILE"
}

do_stop() {
    [[ -f "$STATE_FILE" ]] || die ".cluster/state not found — is a cluster running here?"
    [[ -f "$COMPOSE_FILE" ]] || die ".cluster/docker-compose.deps.yaml not found"

    local status mode project
    status="$(jq -r '.status' "$STATE_FILE")"
    mode="$(jq -r '.mode' "$STATE_FILE")"
    project="$(jq -r '.project' "$STATE_FILE")"

    if [[ "$status" == "stopped" ]]; then
        echo "Cluster is already stopped."
        return 0
    fi

    echo "Stopping UH services..."
    set +e

    if [[ "$mode" == "native" ]]; then
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
        done < <(jq -r '.pids | values[]' "$STATE_FILE")

        local deadline=$((SECONDS + 7))
        while [[ $SECONDS -lt $deadline ]]; do
            local alive=false
            while IFS= read -r pid; do
                [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && alive=true && break
            done < <(jq -r '.pids | values[]' "$STATE_FILE")
            $alive || break
            sleep 0.3
        done

        while IFS= read -r pid; do
            [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
        done < <(jq -r '.pids | values[]' "$STATE_FILE")
    else
        while IFS= read -r container; do
            [[ -n "$container" ]] && docker rm -f "$container" 2>/dev/null
        done < <(jq -r '.containers[]' "$STATE_FILE")
    fi

    set -e

    echo "Stopping dependencies..."
    docker compose -f "$COMPOSE_FILE" -p "$project" down --volumes

    jq '.status = "stopped"' "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
    echo "Cluster stopped."
}

do_delete() {
    if [[ -f "$STATE_FILE" ]]; then
        local status
        status="$(jq -r '.status' "$STATE_FILE")"
        [[ "$status" == "running" ]] && do_stop
    fi
    rm -rf "$CLUSTER_DIR"
    echo "Cluster directory removed."
}

[[ $# -ge 1 ]] || usage
check_prerequisites

action="$1"; shift

case "$action" in
    start)  do_start "$@" ;;
    stop)   do_stop ;;
    delete) do_delete ;;
    *)      usage ;;
esac
