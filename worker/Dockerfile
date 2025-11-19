FROM citusdata/citus:13.2.0

# Install additional tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-contrib \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Worker-specific configuration
RUN echo "# Citus Worker Configuration" > /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "set -e" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo 'psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL' >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "    CREATE EXTENSION IF NOT EXISTS citus;" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "    ALTER SYSTEM SET listen_addresses = '*';" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "    ALTER SYSTEM SET max_connections = 300;" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "    ALTER SYSTEM SET shared_buffers = '256MB';" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    echo "EOSQL" >> /docker-entrypoint-initdb.d/init-worker.sh && \
    chmod +x /docker-entrypoint-initdb.d/init-worker.sh

# Expose PostgreSQL port
EXPOSE 5432