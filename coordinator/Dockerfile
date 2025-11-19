FROM citusdata/citus:13.2.0

# Install additional tools that might be useful
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-contrib \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy initialization script
COPY init-coordinator.sh /docker-entrypoint-initdb.d/

# Ensure script is executable
RUN chmod +x /docker-entrypoint-initdb.d/init-coordinator.sh

# Set proper ownership
RUN chown -R postgres:postgres /docker-entrypoint-initdb.d/

# Expose PostgreSQL port
EXPOSE 5432

# Use the base image's entrypoint
# This will automatically run scripts in /docker-entrypoint-initdb.d/