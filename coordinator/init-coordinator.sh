#!/bin/bash
set -e

echo "Initializing Citus Coordinator..."

# This script runs on coordinator initialization
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create Citus extension
    CREATE EXTENSION IF NOT EXISTS citus;
    
    -- Useful extensions for monitoring and operations
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    
    -- Configure coordinator settings for distributed queries
    ALTER SYSTEM SET wal_level = 'logical';
    ALTER SYSTEM SET max_wal_senders = 10;
    ALTER SYSTEM SET max_replication_slots = 10;
    
    -- Optimize for distributed queries
    ALTER SYSTEM SET max_connections = 300;
    ALTER SYSTEM SET shared_buffers = '256MB';
    ALTER SYSTEM SET effective_cache_size = '1GB';
    ALTER SYSTEM SET maintenance_work_mem = '128MB';
    ALTER SYSTEM SET checkpoint_completion_target = 0.9;
    ALTER SYSTEM SET wal_buffers = '16MB';
    ALTER SYSTEM SET default_statistics_target = 100;
    ALTER SYSTEM SET random_page_cost = 1.1;
    ALTER SYSTEM SET effective_io_concurrency = 200;
    
    -- Allow connections from private network
    ALTER SYSTEM SET listen_addresses = '*';
    
    -- Citus configuration
    ALTER SYSTEM SET citus.shard_count = 32;
    ALTER SYSTEM SET citus.shard_replication_factor = 1;
EOSQL

# Update pg_hba.conf to allow worker connections over private network
cat >> "$PGDATA/pg_hba.conf" <<EOF

# Allow Citus workers to connect over private network
host    all             all             10.0.0.0/8              md5
host    all             all             172.16.0.0/12           md5
host    all             all             192.168.0.0/16          md5
EOF

echo "Coordinator initialized successfully"
echo "Citus extension enabled and configured"