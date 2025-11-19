FROM citusdata/citus:13.2.0

# Install network tools for service discovery
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    dnsutils \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Copy registration script
COPY register-workers.sh /register-workers.sh

# Make script executable
RUN chmod +x /register-workers.sh

# This service runs once and exits
ENTRYPOINT ["/bin/bash", "/register-workers.sh"]