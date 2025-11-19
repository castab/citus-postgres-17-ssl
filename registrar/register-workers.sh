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
    
    # Always append .railway.internal for Railway's private network
    local full_host="${worker_host}.railway.internal"
    
    echo "Waiting for $full_host to be ready..."
    
    # Test with netcat first
    until nc -z -w5 "$full_host" 5432 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "✗ Timeout waiting for $full_host"
            return 1
        fi
        echo "  $full_host not ready yet (attempt $attempt/$max_attempts)..."
        sleep 5
    done
    
    # Additional check with psql
    until PGPASSWORD=$POSTGRES_PASSWORD psql -h "$full_host" -U "$POSTGRES_USER" -d postgres -c '\q' 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "✗ Timeout waiting for $full_host PostgreSQL"
            return 1
        fi
        sleep 2
    done
    
    echo "✓ $full_host is ready"
    return 0
}

# Function to register a worker
register_worker() {
    local worker_host=$1
    local worker_port=${2:-5432}
    
    # Always use .railway.internal suffix for Railway
    local full_host="${worker_host}.railway.internal"
    
    echo ""
    echo "Registering worker: $full_host:$worker_port"
    
    # Check if worker is already registered
    local existing=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -tA -c \
        "SELECT COUNT(*) FROM pg_dist_node WHERE nodename = '$full_host' AND nodeport = $worker_port;")
    
    if [ "$existing" != "0" ]; then
        echo "✓ Worker $full_host already registered, skipping"
        return 0
    fi
    
    # Register the worker
    if PGPASSWORD=$POSTGRES_PASSWORD psql -h "$COORDINATOR_HOST" -U "$POSTGRES_USER" -d postgres -c \
        "SELECT * FROM citus_add_node('$full_host', $worker_port);" >/dev/null 2>&1; then
        echo "✓ Successfully registered worker: $full_host"
        return 0
    else
        echo "✗ Failed to register worker: $full_host"
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
echo "DEBUG: Testing DNS resolution for worker services..."

for i in {1..20}; do
    worker_name="worker$i"
    
    # Check both formats: with and without .railway.internal
    echo "  Checking: $worker_name"
    
    # Try with .railway.internal first (more reliable on Railway)
    if getent hosts "${worker_name}.railway.internal" >/dev/null 2>&1; then
        echo "✓ Discovered: $worker_name (via getent hosts)"
        discovered_workers+=("$worker_name")
        continue
    fi
    
    # Try without suffix
    if getent hosts "$worker_name" >/dev/null 2>&1; then
        echo "✓ Discovered: $worker_name (direct)"
        discovered_workers+=("$worker_name")
        continue
    fi
    
    # Fallback: Try parsing host output even if exit code is non-zero
    # Railway DNS sometimes returns addresses but with NOTIMP error code
    host_output=$(host "${worker_name}.railway.internal" 2>&1)
    if echo "$host_output" | grep -q "has address\|has IPv6 address"; then
        echo "✓ Discovered: $worker_name (via host command with address)"
        discovered_workers+=("$worker_name")
        continue
    fi
done

echo ""
echo "DEBUG: Discovered workers array: ${discovered_workers[@]}"

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