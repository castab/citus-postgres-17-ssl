# Citus Distributed PostgreSQL Cluster

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/citus-postgres-17-cluster)

A production-ready Citus distributed PostgreSQL cluster with 1 coordinator and 2 worker nodes. Easily scale horizontally by distributing your data across multiple nodes.

## What is Citus?

Citus is a PostgreSQL extension that transforms Postgres into a distributed database. It enables you to:

- **Scale out PostgreSQL** - Distribute tables across multiple nodes
- **Run queries in parallel** - Execute queries across all nodes simultaneously
- **Maintain PostgreSQL compatibility** - Use standard PostgreSQL tools and extensions
- **Achieve high performance** - Handle millions of events per second

## Architecture

This template deploys a 3-node Citus cluster:

- **1 Coordinator Node** - Query router and metadata store
- **2 Worker Nodes** - Distributed data storage and query execution

All nodes communicate over Railway's private network for optimal performance and security.

## Features

✅ Automatic worker registration  
✅ Private network communication  
✅ Persistent data volumes  
✅ Health checks on all nodes  
✅ Ready for Patroni HA integration  
✅ PostgreSQL 17 with Citus 13.2  

## Getting Started

### 1. Deploy to Railway

Click the "Deploy on Railway" button above. The template will automatically:
- Deploy 3 PostgreSQL instances with Citus enabled
- Configure private networking between nodes
- Register workers with the coordinator
- Set up persistent volumes for data storage

### 2. Connect to Your Cluster

After deployment, connect to the coordinator using the provided `DATABASE_URL`:

```bash
psql $DATABASE_URL
```

### 3. Create Your First Distributed Table

```sql
-- Create a table
CREATE TABLE events (
    device_id bigint,
    event_time timestamptz,
    event_type text,
    payload jsonb
);

-- Distribute the table across worker nodes
SELECT create_distributed_table('events', 'device_id');

-- Insert data - it will automatically distribute across workers
INSERT INTO events VALUES 
    (1, now(), 'click', '{"button": "submit"}'),
    (2, now(), 'view', '{"page": "home"}');

-- Queries run in parallel across all workers
SELECT event_type, count(*) 
FROM events 
GROUP BY event_type;
```

## Environment Variables

The template automatically configures these variables:

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | Database superuser (default: postgres) |
| `POSTGRES_PASSWORD` | Superuser password (auto-generated) |
| `POSTGRES_DB` | Default database name |
| `DATABASE_URL` | Full connection string for coordinator |

## Scaling

> 📖 **For detailed scaling instructions, see [SCALING.md](SCALING.md)**

### Adding More Workers (Horizontal Scaling)

The cluster automatically discovers and registers new workers! To add additional worker nodes:

1. **In Railway Dashboard**, go to your project
2. **Duplicate** any existing worker service (right-click → Duplicate)
3. **Rename** the new service to `worker3` (or `worker4`, `worker5`, etc.)
4. **Deploy** the service
5. **Automatic registration**: The registrar will discover and register the new worker on its next run

Alternatively, you can manually trigger registration:

```bash
# Connect to coordinator
psql $DATABASE_URL

# Manually add the new worker
SELECT citus_add_node('worker3.railway.internal', 5432);

# Verify it was added
SELECT * FROM citus_get_active_worker_nodes();
```

**Supported naming patterns:**
- `worker1`, `worker2`, `worker3`, ... `worker20`
- `worker-1`, `worker-2`, etc.
- `citus-worker1`, `citus-worker-1`, etc.

The registrar automatically scans for up to 20 workers using these patterns.

### Removing Workers

Before removing a worker:

```sql
-- Move data off the worker
SELECT citus_drain_node('worker3.railway.internal', 5432);

-- Remove from cluster
SELECT citus_remove_node('worker3.railway.internal', 5432);
```

Then delete the service from Railway.

### Vertical Scaling

Increase CPU and memory for individual nodes through Railway's service settings based on your workload requirements.

**Recommended resource allocation:**
- **Coordinator**: 2-4 vCPU, 4-8GB RAM (handles all queries)
- **Workers**: 2-4 vCPU, 4-8GB RAM each (scale based on data volume)

## Network Architecture

All services communicate over Railway's private network:

```
Coordinator (Public)
    ↓ (private network)
Worker 1 (Private)
Worker 2 (Private)
```

Only the coordinator is exposed publicly. Workers communicate exclusively over the private network for security and performance.

## 📚 Documentation

- **[Quick Reference](QUICK_REFERENCE.md)** - Common commands and operations
- **[Scaling Guide](SCALING.md)** - How to scale your cluster horizontally and vertically  
- **[Troubleshooting](TROUBLESHOOTING.md)** - Solutions to common issues
- **[Railway Setup](RAILWAY_SETUP.md)** - For template maintainers

## Citus Resources

- [Citus Documentation](https://docs.citusdata.com/)
- [Distributed Table Design](https://docs.citusdata.com/en/stable/sharding/data_modeling.html)
- [Query Performance](https://docs.citusdata.com/en/stable/performance/performance_tuning.html)
- [Multi-Tenant Applications](https://docs.citusdata.com/en/stable/use_cases/multi_tenant.html)

## Use Cases

**Multi-Tenant SaaS** - Isolate tenant data while sharing infrastructure  
**Real-Time Analytics** - Ingest and query high volumes of time-series data  
**Event Streaming** - Process millions of events per second  
**IoT Applications** - Scale to billions of device measurements  

## Patroni Integration (Coming Soon)

This template is structured to support Patroni high-availability. Each node can be independently managed by Patroni for automatic failover while maintaining Citus cluster functionality.

## Support

For issues specific to this Railway template, please open an issue in the repository.

For Citus-related questions, visit the [Citus Community Slack](https://www.citusdata.com/slack).

## License

This template is MIT licensed. Citus is available under the AGPLv3 license.