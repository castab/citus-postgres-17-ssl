# Scaling Your Citus Cluster on Railway

This guide covers how to scale your Citus cluster both horizontally (more workers) and vertically (more resources per node).

## Quick Start: Adding Your First Additional Worker

1. Go to your Railway project dashboard
2. Right-click on any `worker` service → **Duplicate**
3. Rename the duplicated service to `worker3`
4. Click **Deploy**
5. Done! Your cluster now has 3 workers

The registrar service automatically discovers and registers new workers.

## Horizontal Scaling (Add More Workers)

### Automatic Discovery

The cluster uses **dynamic worker discovery**. Any service matching these patterns is automatically found and registered:

| Pattern | Examples |
|---------|----------|
| `workerN` | worker1, worker2, worker3, ... worker20 |
| `worker-N` | worker-1, worker-2, worker-3 |
| `citus-workerN` | citus-worker1, citus-worker2 |
| `citus-worker-N` | citus-worker-1, citus-worker-2 |

### Step-by-Step: Adding Workers

#### Method 1: Duplicate Service (Easiest)

1. **Duplicate an existing worker**:
   - Right-click `worker1` or `worker2` → Duplicate
   - Or click the service → Settings → Duplicate

2. **Rename the service**:
   - Change name to `worker3` (or next available number)
   - Keep all other settings the same

3. **Deploy**:
   - Railway will automatically deploy the new service
   - Wait for healthy status

4. **Verify registration** (optional):
   ```bash
   psql $DATABASE_URL -c "SELECT * FROM citus_get_active_worker_nodes();"
   ```

#### Method 2: Create New Service from Template

1. **Create new service** in your project:
   - Add Service → GitHub Repo
   - Select your template repository
   - Root directory: `worker`
   - Dockerfile path: `worker/Dockerfile`

2. **Name it**: `worker3`, `worker4`, etc.

3. **Configure environment variables**:
   ```
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=${{ coordinator.POSTGRES_PASSWORD }}
   POSTGRES_DB=postgres
   PGDATA=/var/lib/postgresql/data/pgdata
   ```

4. **Add volume**:
   - Mount path: `/var/lib/postgresql/data`

5. **Keep private**: No public networking needed

6. **Deploy**

#### Method 3: Manual Registration

If automatic discovery doesn't work, manually register:

```sql
-- Connect to coordinator
psql $DATABASE_URL

-- Add the worker
SELECT citus_add_node('worker3.railway.internal', 5432);

-- Verify
SELECT nodename, nodeport FROM citus_get_active_worker_nodes();
```

### When to Add More Workers

Add workers when you need:

- **More storage capacity**: Each worker stores a portion of your data
- **Better query parallelism**: More workers = more parallel query execution
- **Higher write throughput**: Writes are distributed across workers
- **Data isolation**: In multi-tenant apps, you can colocate tenant data on specific workers

### Scaling Limits

- **Maximum workers**: Typically 20-50 workers depending on your workload
- **Coordinator bottleneck**: The coordinator coordinates all queries; scale it vertically if it becomes a bottleneck
- **Network overhead**: More workers = more cross-worker communication
- **Cost**: Each worker is a separate Railway service with its own costs

## Horizontal Scaling (Remove Workers)

### Safe Worker Removal

**⚠️ IMPORTANT**: Never just delete a worker service! You'll lose data.

#### Step 1: Drain the Worker

Move all data off the worker before removal:

```sql
-- Connect to coordinator
psql $DATABASE_URL

-- Drain the worker (moves shards to other workers)
SELECT citus_drain_node('worker3.railway.internal', 5432);

-- This may take a while depending on data volume
-- Monitor progress:
SELECT * FROM pg_dist_placement WHERE groupid = (
    SELECT groupid FROM pg_dist_node 
    WHERE nodename = 'worker3.railway.internal'
);
```

#### Step 2: Remove from Cluster

```sql
-- Remove the node from Citus metadata
SELECT citus_remove_node('worker3.railway.internal', 5432);

-- Verify removal
SELECT * FROM citus_get_active_worker_nodes();
```

#### Step 3: Delete Railway Service

Now it's safe to delete the worker service from Railway:
1. Go to service settings
2. Scroll to bottom → Delete Service

### What Happens During Removal

- Data is **rebalanced** to remaining workers
- Queries are **rerouted** to active workers
- No downtime if done correctly
- Rebalancing can take time for large datasets

## Vertical Scaling (More Resources)

### When to Scale Vertically

Scale up resources when:

- **CPU usage consistently high** (>80%)
- **Memory pressure** (high swap, OOM errors)
- **Slow queries** that could benefit from more cache
- **High connection count** needs more memory

### Coordinator Scaling

The coordinator handles all query planning and routing:

**Small cluster (< 100GB total)**:
- 2 vCPU, 4GB RAM

**Medium cluster (100GB - 1TB)**:
- 4 vCPU, 8GB RAM

**Large cluster (> 1TB)**:
- 8 vCPU, 16GB RAM

**To scale**:
1. Go to coordinator service → Settings
2. Scroll to Resources
3. Adjust CPU and RAM
4. Click Save (Railway will restart the service)

### Worker Scaling

Workers store and process data:

**Per-worker recommendations**:
- **Light workload**: 2 vCPU, 4GB RAM
- **Medium workload**: 4 vCPU, 8GB RAM  
- **Heavy workload**: 8 vCPU, 16GB RAM

**Note**: You don't need to scale all workers equally. Scale based on actual usage.

**To scale**:
1. Go to worker service → Settings
2. Adjust Resources
3. Save (no data loss during restart)

### Storage Scaling

Railway automatically handles storage scaling:
- Volumes grow as needed
- No manual intervention required
- You're charged for actual usage

Monitor storage usage:

```sql
-- Check database sizes per worker
SELECT 
    nodename,
    pg_size_pretty(sum(shard_size)) as total_size
FROM citus_shards
GROUP BY nodename;
```

## Rebalancing After Scaling

### When to Rebalance

After adding workers, you may want to rebalance:
- To evenly distribute existing data
- To improve query performance
- To balance disk usage

### How to Rebalance

```sql
-- See current shard distribution
SELECT nodename, count(*) as shard_count
FROM citus_shards
GROUP BY nodename
ORDER BY shard_count DESC;

-- Rebalance shards across all workers
SELECT citus_rebalance_start();

-- Monitor rebalancing progress
SELECT * FROM citus_rebalance_status();

-- Wait for completion (can take hours for large datasets)
```

### Rebalancing Strategies

**By shard count** (default):
```sql
SELECT citus_rebalance_start(
    rebalance_strategy := 'by_shard_count'
);
```

**By disk size**:
```sql
SELECT citus_rebalance_start(
    rebalance_strategy := 'by_disk_size'
);
```

**Drain specific nodes**:
```sql
-- Move data off specific nodes
SELECT citus_rebalance_start(
    drain_only := ARRAY['worker1.railway.internal']
);
```

## Scaling Strategies by Use Case

### Multi-Tenant SaaS
- Start with 2 workers
- Add workers as you add tenants
- Use tenant_id as distribution column
- Colocate related tables

### Real-Time Analytics
- Start with 4-6 workers for parallelism
- Scale coordinator CPU for query planning
- Add workers for more data retention

### Time-Series Data
- Add workers monthly/quarterly as data grows
- Consider time-based sharding
- Archive old data to cheaper storage

### High-Traffic Application
- Scale coordinator vertically first
- Add workers for write throughput
- Use connection pooling (pgBouncer)

## Monitoring Scaling Needs

### Key Metrics to Watch

**Coordinator**:
```sql
-- Connection count
SELECT count(*) FROM pg_stat_activity;

-- Query duration
SELECT query, state, wait_event, query_start 
FROM pg_stat_activity 
WHERE query != '<IDLE>' 
ORDER BY query_start;

-- Cache hit ratio (should be > 90%)
SELECT 
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as cache_hit_ratio
FROM pg_statio_user_tables;
```

**Workers**:
```sql
-- Disk usage per worker
SELECT 
    nodename,
    pg_size_pretty(sum(shard_size)) as size
FROM citus_shards
GROUP BY nodename;

-- Shard distribution
SELECT 
    nodename,
    count(*) as shard_count,
    count(*) * 100.0 / sum(count(*)) OVER () as percentage
FROM citus_shards
GROUP BY nodename;
```

### Railway Metrics

Monitor in Railway dashboard:
- **CPU usage**: Should average < 70%
- **Memory**: Should have 20%+ free
- **Network**: Watch for high egress costs
- **Disk**: Railway alerts at 80% full

## Cost Optimization

### Right-Sizing

- Don't over-provision initially
- Start small, scale based on actual metrics
- Review usage monthly

### Cost-Effective Scaling

**Instead of**: 4 small workers (1 vCPU, 2GB each)  
**Consider**: 2 larger workers (2 vCPU, 4GB each)

Larger workers are more cost-effective per unit of resources.

### Free Tier Optimization

Railway free tier includes $5/month credit:
- 1 coordinator (small): ~$2-3/month
- 2 workers (small): ~$4-6/month
- Registrar: Free (runs once)

**Fits in free tier!** Great for development and small projects.

## Troubleshooting Scaling Issues

### Worker Not Discovered

**Problem**: New worker not appearing in cluster

**Solution**:
```bash
# Check worker is healthy
curl -f http://worker3.railway.internal:5432 || echo "Not reachable"

# Check DNS resolution
nslookup worker3.railway.internal

# Manually register
psql $DATABASE_URL -c "SELECT citus_add_node('worker3.railway.internal', 5432);"
```

### Uneven Data Distribution

**Problem**: Some workers have much more data than others

**Solution**:
```sql
-- Check distribution
SELECT nodename, count(*) FROM citus_shards GROUP BY nodename;

-- Rebalance
SELECT citus_rebalance_start();
```

### High Coordinator CPU

**Problem**: Coordinator CPU consistently > 80%

**Solution**:
1. Scale coordinator vertically first
2. Check for slow queries: `SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;`
3. Add indexes on distributed tables
4. Consider query optimization

### Disk Space Issues

**Problem**: Worker running out of disk space

**Solution**:
```sql
-- Find large tables
SELECT 
    logicalrelid,
    pg_size_pretty(citus_table_size(logicalrelid))
FROM pg_dist_partition
ORDER BY citus_table_size(logicalrelid) DESC;

-- Option 1: Add more workers and rebalance
-- Option 2: Archive old data
-- Option 3: Increase shard count (requires recreating table)
```

## Best Practices

✅ **Start small**: Begin with 2 workers, scale based on metrics  
✅ **Monitor first**: Watch metrics before scaling  
✅ **Scale gradually**: Add 1-2 workers at a time  
✅ **Test rebalancing**: In staging environment first  
✅ **Backup before scaling**: Always have recent backups  
✅ **Document changes**: Note why you scaled and results  
✅ **Use rebalancing**: After adding workers  
✅ **Balance cost vs performance**: Don't over-provision  

❌ **Don't**: Remove workers without draining  
❌ **Don't**: Scale all services simultaneously  
❌ **Don't**: Ignore monitoring data  
❌ **Don't**: Forget to rebalance after adding workers  

## Quick Reference

| Action | Command |
|--------|---------|
| List workers | `SELECT * FROM citus_get_active_worker_nodes();` |
| Add worker | `SELECT citus_add_node('workerN.railway.internal', 5432);` |
| Remove worker | `SELECT citus_remove_node('workerN.railway.internal', 5432);` |
| Drain worker | `SELECT citus_drain_node('workerN.railway.internal', 5432);` |
| Rebalance | `SELECT citus_rebalance_start();` |
| Check rebalancing | `SELECT * FROM citus_rebalance_status();` |
| Shard distribution | `SELECT nodename, count(*) FROM citus_shards GROUP BY nodename;` |

---

For more details, see:
- [Citus Shard Rebalancing](https://docs.citusdata.com/en/stable/admin_guide/cluster_management.html#rebalancing-shards)
- [Railway Resource Limits](https://docs.railway.app/reference/deployment)