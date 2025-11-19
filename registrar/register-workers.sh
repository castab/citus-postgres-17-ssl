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
echo "  - worker-1, worker-2, worker-3, ..."
echo "  - citus-worker1, citus-worker-1, etc."
echo ""
echo "To manually re-run registration after adding workers:"
echo "  Railway Dashboard → registrar service → Deploy"
echo ""
echo "========================================="
echo ""

# Wait for coordinator to be ready
echo "Waiting for coordinator to be ready..."
until PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -c '\q' 2>/dev/null; do
    echo "Coordinator not ready yet, waiting..."
    sleep 5
done
echo "✓ Coordinator is ready"

# Function to wait for a worker to be ready
wait_for_worker() {
    local worker_host=$1
    local max_attempts=30
    local attempt=0
    
    echo "Waiting for $worker_host to be ready..."
    until nc -z -w5 "$worker_host" 5432 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "✗ Timeout waiting for $worker_host"
            return 1
        fi
        echo "  $worker_host not ready yet (attempt $attempt/$max_attempts)..."
        sleep 5
    done
    
    # Additional check with psql
    until PGPASSWORD=$POSTGRES_PASSWORD psql -h "$worker_host" -U "$POSTGRES_USER" -d postgres -c '\q' 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "✗ Timeout waiting for $worker_host PostgreSQL"
            return 1
        fi
        sleep 2
    done
    
    echo "✓ $worker_host is ready"
    return 0
}

# Function to register a worker
register_worker() {
    local worker_host=$1
    local worker_port=${2:-5432}
    
    echo ""
    echo "Registering worker: $worker_host:$worker_port"
    
    # Check if worker is already registered
    local existing=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -tA -c \
        "SELECT COUNT(*) FROM pg_dist_node WHERE nodename = '$worker_host' AND nodeport = $worker_port;")
    
    if [ "$existing" != "0" ]; then
        echo "✓ Worker $worker_host already registered, skipping"
        return 0
    fi
    
    # Register the worker
    if PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -c \
        "SELECT * FROM citus_add_node('$worker_host', $worker_port);" >/dev/null 2>&1; then
        echo "✓ Successfully registered worker: $worker_host"
        return 0
    else
        echo "✗ Failed to register worker: $worker_host"
        return 1
    fi
}

# Discover and register workers using Railway's private network DNS
# Railway services are accessible via their service name on the private network
echo ""
echo "Discovering workers on Railway private network..."

# Dynamic worker discovery - finds any service named "worker*"
# This allows users to add worker3, worker4, etc. after deployment
discovered_workers=()

# Method 1: Try common worker names (worker1-20)
echo "Scanning for worker services..."
for i in {1..20}; do
    worker_name="worker$i"
    
    # Check if the hostname resolves (DNS lookup)
    if host "$worker_name" >/dev/null 2>&1; then
        echo "✓ Discovered: $worker_name"
        discovered_workers+=("$worker_name")
    fi
done

# Method 2: Also check for workers with different naming patterns
# (e.g., worker-1, citus-worker-1, etc.)
for pattern in "worker-" "citus-worker" "citus-worker-"; do
    for i in {1..20}; do
        worker_name="${pattern}${i}"
        if host "$worker_name" >/dev/null 2>&1; then
            # Check if not already in array
            if [[ ! " ${discovered_workers[@]} " =~ " ${worker_name} " ]]; then
                echo "✓ Discovered: $worker_name"
                discovered_workers+=("$worker_name")
            fi
        fi
    done
done

# Register all discovered workers
if [ ${#discovered_workers[@]} -eq 0 ]; then
    echo ""
    echo "⚠ WARNING: No worker services discovered!"
    echo "Expected worker services like: worker1, worker2, etc."
    echo "Make sure worker services are deployed and accessible on the private network."
    echo ""
else
    echo ""
    echo "Found ${#discovered_workers[@]} worker service(s)"
    echo ""
    
    # Register each discovered worker
    for worker in "${discovered_workers[@]}"; do
        if wait_for_worker "$worker"; then
            register_worker "$worker" 5432
        else
            echo "⚠ Skipping $worker (not responding)"
        fi
    done
fi

echo ""
echo "========================================="
echo "Verifying Citus Cluster Configuration"
echo "========================================="

# Verify cluster setup
PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres <<-EOSQL
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

# Count registered workers
WORKER_COUNT=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -tA -c \
    "SELECT COUNT(*) FROM pg_dist_node WHERE noderole = 'primary' AND groupid > 0;")

echo ""
echo "========================================="
echo "Registration Summary"
echo "========================================="
echo "Registered workers: $WORKER_COUNT"
echo "Coordinator: $COORDINATOR_HOST"
echo ""

if [ "$WORKER_COUNT" -gt 0 ]; then
    echo "✓ Citus cluster is ready!"
    echo ""
    echo "Next steps:"
    echo "1. Connect to coordinator: psql \$DATABASE_URL"
    echo "2. Create a distributed table:"
    echo "   SELECT create_distributed_table('your_table', 'distribution_column');"
    echo ""
else
    echo "⚠ No workers registered. Cluster is running but not distributed."
    echo "Check that worker services are running and accessible."
fi

echo "========================================="
echo "Worker registration complete!"
echo "========================================="