#!/bin/bash
set -e

echo "========================================="
echo "Citus Worker Registration Service"
echo "========================================="
echo ""
echo "This service automatically discovers and registers"
echo "all worker nodes with the coordinator."
echo ""
echo "Supported naming patterns:"
echo "  - worker1, worker2, worker3, ..."
echo ""
echo "To manually re-run registration after adding workers:"
echo "  Railway Dashboard → registrar service → Deploy"
echo ""
echo "========================================="
echo ""

# -------------------------------------------------------------
# Safety Wrappers (like try/catch for bash)
# -------------------------------------------------------------

safe_getent() {
    # Returns 0 only if hostname resolves
    getent hosts "$1" >/dev/null 2>&1 || return 1
}

safe_host() {
    # host(1) often returns NOTIMP but output still contains usable IPs
    local out
    out=$(host "$1" 2>&1 || true)
    echo "$out"
}

safe_nc() {
    # nc should never break the script
    nc -z -w5 "$1" "$2" >/dev/null 2>&1 || return 1
}

safe_psql() {
    # psql check without breaking script
    PGPASSWORD=$POSTGRES_PASSWORD psql \
        -h "$1" -U "$POSTGRES_USER" -d postgres \
        -c '\q' >/dev/null 2>&1 || return 1
}

# -------------------------------------------------------------
# Wait for coordinator
# -------------------------------------------------------------
echo "Waiting for coordinator to be ready..."
until safe_psql "$COORDINATOR_HOST"; do
    echo "Coordinator not ready yet, waiting..."
    sleep 5
done
echo "✓ Coordinator is ready!"


# -------------------------------------------------------------
# Wait for worker
# -------------------------------------------------------------
wait_for_worker() {
    local worker_host=$1
    local max_attempts=30
    local attempt=0
    local full_host="${worker_host}.railway.internal"

    echo "Waiting for $full_host to be ready..."

    # 1. Wait for TCP port
    until safe_nc "$full_host" 5432; do
        attempt=$(( attempt + 1 ))
        if [ $attempt -ge $max_attempts ]; then
            echo "✗ Timeout waiting for $full_host"
            return 1
        fi
        echo "  $full_host not ready (attempt $attempt/$max_attempts)"
        sleep 5
    done

    # 2. Wait for PostgreSQL
    until safe_psql "$full_host"; do
        attempt=$(( attempt + 1 ))
        if [ $attempt -ge $max_attempts ]; then
            echo "✗ Timeout waiting for $full_host PostgreSQL"
            return 1
        fi
        sleep 2
    done

    echo "✓ $full_host is ready"
    return 0
}


# -------------------------------------------------------------
# Register worker
# -------------------------------------------------------------
register_worker() {
    local worker_host=$1
    local port=${2:-5432}
    local full_host="${worker_host}.railway.internal"

    echo ""
    echo "Registering worker: $full_host:$port"

    # Check existing
    local existing
    existing=$(PGPASSWORD=$POSTGRES_PASSWORD psql \
        -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -tA -c \
        "SELECT COUNT(*) FROM pg_dist_node WHERE nodename = '$full_host' AND nodeport = $port;" || echo "0")

    if [ "$existing" != "0" ]; then
        echo "✓ Worker already registered, skipping"
        return 0
    fi

    # Try registration
    if PGPASSWORD=$POSTGRES_PASSWORD psql \
        -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -c \
        "SELECT * FROM citus_add_node('$full_host', $port);" >/dev/null 2>&1; then
        echo "✓ Successfully registered worker: $full_host"
        return 0
    else
        echo "✗ Failed to register worker: $full_host"
        return 1
    fi
}


# -------------------------------------------------------------
# Discover workers
# -------------------------------------------------------------
echo ""
echo "Discovering workers on Railway private network..."
discovered_workers=()

echo "Scanning for worker services..."

for i in {1..20}; do
    worker_name="worker$i"
    full_host="${worker_name}.railway.internal"

    echo "  Checking: $worker_name"

    # 1. Try getent with suffix first
    if safe_getent "$full_host"; then
        echo "✓ Discovered: $worker_name (getent .railway.internal)"
        discovered_workers+=("$worker_name")
        continue
    fi

    # 2. Try direct hostname
    if safe_getent "$worker_name"; then
        echo "✓ Discovered: $worker_name (getent direct)"
        discovered_workers+=("$worker_name")
        continue
    fi

    # 3. Parse host output
    host_output=$(safe_host "$full_host")
    if echo "$host_output" | grep -Eq "has address|has IPv6 address"; then
        echo "✓ Discovered: $worker_name (via host output)"
        discovered_workers+=("$worker_name")
        continue
    fi
done

echo ""
echo "DEBUG: Discovered workers: ${discovered_workers[@]}"


# -------------------------------------------------------------
# Register workers
# -------------------------------------------------------------
if [ ${#discovered_workers[@]} -eq 0 ]; then
    echo ""
    echo "⚠ WARNING: No workers discovered!"
    echo "Ensure worker services exist: worker1, worker2, etc."
    echo ""
else
    echo ""
    echo "Found ${#discovered_workers[@]} worker(s)."
    echo ""

    for worker in "${discovered_workers[@]}"; do
        if wait_for_worker "$worker"; then
            register_worker "$worker"
        else
            echo "⚠ Skipping $worker (never became ready)"
        fi
    done
fi


# -------------------------------------------------------------
# Verify cluster
# -------------------------------------------------------------
echo ""
echo "========================================="
echo "Verifying Citus Cluster Configuration"
echo "========================================="

PGPASSWORD=$POSTGRES_PASSWORD psql \
    -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres <<-EOSQL
    SELECT 
        nodename AS "Node",
        nodeport AS "Port",
        CASE 
            WHEN noderole = 'primary' THEN 'coordinator'
            ELSE 'worker'
        END AS "Role"
    FROM pg_dist_node
    ORDER BY nodename;
EOSQL

WORKER_COUNT=$(PGPASSWORD=$POSTGRES_PASSWORD psql \
    -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -tA -c \
    "SELECT COUNT(*) FROM pg_dist_node WHERE groupid > 0;" || echo "0")

echo ""
echo "========================================="
echo "Registration Summary"
echo "========================================="
echo "Registered workers: $WORKER_COUNT"
echo "Coordinator: $COORDINATOR_HOST"
echo ""

if [ "$WORKER_COUNT" -gt 0 ]; then
    echo "✓ Citus cluster is ready!"
else
    echo "⚠ No workers registered. Cluster runs as single node."
fi

echo "========================================="
echo "Worker registration complete!"
echo "========================================="
