# Troubleshooting Guide

Common issues and solutions for your Citus cluster on Railway.

## Workers Not Appearing

### Symptom
After adding a new worker, it doesn't show up in the cluster:

```sql
SELECT * FROM citus_get_active_worker_nodes();
-- New worker is missing
```

### Diagnosis

1. **Check worker is deployed and healthy**:
   - Go to Railway dashboard
   - Verify worker service shows "Active" status
   - Check the worker service logs for errors

2. **Verify naming pattern**:
   - Worker must be named: `worker1`, `worker2`, `worker3`, etc.
   - Or: `worker-1`, `citus-worker1`, etc.
   - Case-sensitive on some systems

3. **Check private network connectivity**:
   ```bash
   # From coordinator service, try:
   nslookup worker3.railway.internal
   nc -zv worker3.railway.internal 5432
   ```

### Solution

**Option 1: Re-run registrar**
1. Go to Railway dashboard → `registrar` service
2. Click "Deploy" to trigger re-deployment
3. Watch logs to see if worker is discovered

**Option 2: Manual registration**
```sql
-- Connect to coordinator
psql $DATABASE_URL

-- Manually add the worker
SELECT citus_add_node('worker3.railway.internal', 5432);

-- Verify
SELECT * FROM citus_get_active_worker_nodes();
```

**Option 3: Check registrar logs**
```bash
# In Railway dashboard, view registrar logs
# Look for messages like:
# "✓ Discovered: worker3"
# "✓ Successfully registered worker: worker3"
```

---

## Connection Refused

### Symptom
Cannot connect to coordinator from external application:
```
psql: error: connection to server failed: Connection refused
```

### Diagnosis

1. **Check if coordinator has public networking**:
   - Railway dashboard → coordinator service → Settings
   - Should have a public domain assigned

2. **Verify connection string**:
   - Use the Railway-provided `DATABASE_URL`
   - Or use public domain: `coordinator-xxx.railway.app`

3. **Check if coordinator is running**:
   - Look at service status in Railway dashboard
   - Check coordinator logs for errors

### Solution

**Enable public networking**:
1. Go to coordinator service → Settings → Networking
2. Click "Generate Domain"
3. Use the provided URL: `postgresql://postgres:password@coordinator-xxx.railway.app:5432/postgres`

**Update connection string**:
```bash
# Use Railway's variable reference
DATABASE_URL=${{ coordinator.DATABASE_URL }}

# Or construct manually
postgresql://${{ coordinator.POSTGRES_USER }}:${{ coordinator.POSTGRES_PASSWORD }}@${{ coordinator.RAILWAY_PUBLIC_DOMAIN }}:5432/postgres
```

---

## Workers Can't Connect to Coordinator

### Symptom
Workers show errors in logs:
```
FATAL: password authentication failed for user "postgres"
```

### Diagnosis

1. **Check password consistency**:
   - All services should use: `${{ coordinator.POSTGRES_PASSWORD }}`
   - Check each worker's environment variables

2. **Verify pg_hba.conf settings**:
   ```bash
   # Connect to coordinator
   psql $DATABASE_URL
   
   # Check authentication config
   SHOW hba_file;
   ```

### Solution

**Fix environment variables**:
1. Go to each worker service → Variables
2. Ensure `POSTGRES_PASSWORD` references coordinator:
   ```
   POSTGRES_PASSWORD=${{ coordinator.POSTGRES_PASSWORD }}
   ```
3. Redeploy workers

**Check pg_hba.conf** (should be set by init script):
```
# Should include these lines:
host    all    all    10.0.0.0/8       md5
host    all    all    172.16.0.0/12    md5
host    all    all    192.168.0.0/16   md5
```

---

## Data Not Distributing

### Symptom
Created a table but data stays on coordinator:

```sql
SELECT * FROM citus_tables;
-- Table not listed
```

### Diagnosis

1. **Check if table was distributed**:
   ```sql
   SELECT * FROM pg_dist_partition;
   ```

2. **Verify workers are registered**:
   ```sql
   SELECT * FROM citus_get_active_worker_nodes();
   ```

### Solution

**Distribute the table**:
```sql
-- For regular tables
SELECT create_distributed_table('your_table', 'distribution_column');

-- For reference tables (small lookup tables)
SELECT create_reference_table('small_table');

-- Verify distribution
SELECT * FROM citus_tables;
```

**Common mistakes**:
- ❌ Creating table without distributing it
- ❌ Using wrong distribution column (should be high cardinality)
- ❌ No workers registered yet

---

## Slow Queries

### Symptom
Queries taking much longer than expected on distributed tables.

### Diagnosis

1. **Check query plan**:
   ```sql
   EXPLAIN ANALYZE SELECT * FROM your_distributed_table WHERE ...;
   ```

2. **Look for**:
   - Full table scans across all shards
   - Filters on non-distribution columns
   - Joins without colocation

3. **Check resource usage**:
   - Railway dashboard → Each service → Metrics
   - Look for CPU/memory bottlenecks

### Solution

**Optimize distribution**:
```sql
-- Ensure you're filtering on distribution column
SELECT * FROM orders WHERE customer_id = 123;  -- Good!
SELECT * FROM orders WHERE order_date = '2024-01-01';  -- May be slow

-- Colocate related tables
SELECT create_distributed_table('orders', 'customer_id');
SELECT create_distributed_table('order_items', 'customer_id', colocate_with => 'orders');
```

**Add indexes**:
```sql
-- Create indexes on distributed tables
CREATE INDEX idx_orders_date ON orders(order_date);

-- This creates indexes on all shards across workers
```

**Scale resources**:
- See [SCALING.md](SCALING.md) for guidance
- Scale coordinator if query planning is slow
- Scale workers if query execution is slow

---

## Registrar Keeps Failing

### Symptom
Registrar service shows failed status and keeps restarting.

### Diagnosis

Check registrar logs for specific errors:

```bash
# Common error messages:

# 1. Coordinator not ready
"Coordinator not ready yet, waiting..."

# 2. Worker not reachable
"✗ Timeout waiting for worker3"

# 3. Connection refused
"psql: error: connection to server failed"
```

### Solution

**Coordinator not ready**:
- Wait longer (coordinator can take 1-2 minutes to initialize)
- Check coordinator logs for errors
- Verify coordinator has Citus extension: `\dx` in psql

**Workers not reachable**:
- Check worker services are deployed and healthy
- Verify naming (must be `worker1`, `worker2`, etc.)
- Check Railway's private network status

**Connection refused**:
- Verify all services have same `POSTGRES_PASSWORD`
- Check coordinator's pg_hba.conf allows connections

**Manual override**:
If registrar fails, you can always manually register workers:
```sql
psql $DATABASE_URL -c "SELECT citus_add_node('worker1.railway.internal', 5432);"
psql $DATABASE_URL -c "SELECT citus_add_node('worker2.railway.internal', 5432);"
```

---

## Out of Memory Errors

### Symptom
Service crashes with OOM (Out of Memory) errors in logs:
```
FATAL: out of memory
```

### Diagnosis

1. **Check memory usage**:
   - Railway dashboard → Service → Metrics
   - Look for memory usage at 100%

2. **Identify memory hog**:
   ```sql
   -- Check connection count
   SELECT count(*) FROM pg_stat_activity;
   
   -- Check query memory
   SELECT query, state, wait_event 
   FROM pg_stat_activity 
   WHERE state = 'active';
   
   -- Check shared buffers setting
   SHOW shared_buffers;
   ```

### Solution

**Vertical scaling** (recommended):
1. Railway dashboard → Service → Settings → Resources
2. Increase RAM (2GB → 4GB → 8GB)
3. Redeploy

**Reduce memory usage**:
```sql
-- Reduce shared_buffers if set too high
ALTER SYSTEM SET shared_buffers = '128MB';

-- Reduce work_mem for sorts/hashes
ALTER SYSTEM SET work_mem = '4MB';

-- Reload config
SELECT pg_reload_conf();
```

**Connection pooling**:
- Consider using pgBouncer
- Reduces memory per connection
- Especially important for high-traffic apps

---

## Disk Space Full

### Symptom
Worker service fails with:
```
ERROR: could not extend file: No space left on device
```

### Diagnosis

```sql
-- Check database sizes per worker
SELECT 
    nodename,
    pg_size_pretty(sum(shard_size)) as size
FROM citus_shards
GROUP BY nodename
ORDER BY size DESC;

-- Check specific table sizes
SELECT 
    logicalrelid,
    pg_size_pretty(citus_table_size(logicalrelid)) as size
FROM pg_dist_partition
ORDER BY citus_table_size(logicalrelid) DESC;
```

### Solution

**Option 1: Add more workers**
1. Duplicate a worker service
2. Name it `worker3` (or next number)
3. Rebalance data:
   ```sql
   SELECT citus_rebalance_start();
   ```

**Option 2: Archive old data**
```sql
-- Delete old records
DELETE FROM events WHERE event_time < NOW() - INTERVAL '90 days';

-- Or partition and drop old partitions
```

**Option 3: Increase shard count**
- More shards = better distribution
- Requires recreating table (downtime)
- See Citus docs on shard count tuning

---

## Can't Drop Distributed Table

### Symptom
```sql
DROP TABLE my_table;
-- ERROR: cannot drop table my_table because other objects depend on it
```

### Diagnosis

Table has distributed dependencies (foreign keys, etc.)

### Solution

**Use Citus drop command**:
```sql
-- This handles all distributed dependencies
SELECT citus_drop_distributed_table('my_table');

-- Or CASCADE
DROP TABLE my_table CASCADE;
```

---

## Worker Shows as Inactive

### Symptom
```sql
SELECT * FROM citus_get_active_worker_nodes();
-- Worker appears with isactive = false
```

### Diagnosis

Worker was marked inactive due to:
- Connection timeout
- Health check failure
- Manual deactivation

### Solution

**Reactivate the worker**:
```sql
-- Make the node active again
SELECT citus_activate_node('worker2.railway.internal', 5432);

-- Verify
SELECT * FROM citus_get_active_worker_nodes();
```

**Check worker health**:
```bash
# Test connection
psql -h worker2.railway.internal -U postgres -d postgres -c "SELECT 1;"

# Check worker logs in Railway dashboard
```

---

## Rebalancing Takes Too Long

### Symptom
```sql
SELECT citus_rebalance_start();
-- Process runs for hours
```

### Diagnosis

Rebalancing large amounts of data takes time. This is normal.

### Solution

**Monitor progress**:
```sql
-- Check rebalancing status
SELECT * FROM citus_rebalance_status();

-- See which shards are moving
SELECT * FROM pg_dist_rebalance_strategy;
```

**Speed up rebalancing** (careful!):
```sql
-- Increase parallelism
SET citus.max_adaptive_executor_pool_size = 16;

-- But be careful not to overwhelm workers
```

**Run during off-peak hours**:
- Schedule rebalancing when traffic is low
- Reduces impact on production queries

**Break it up**:
```sql
-- Rebalance one table at a time
SELECT citus_rebalance_start(
    included_tables := ARRAY['large_table']::regclass[]
);
```

---

## Railway-Specific Issues

### Service Won't Deploy

**Check build logs**:
1. Railway dashboard → Service → Deployments
2. Click on failed deployment
3. View build logs for errors

**Common causes**:
- Dockerfile syntax error
- Missing files in repository
- Railway resource limits hit

### Private Network Not Working

**Verify service names**:
- Services must use exact names: `coordinator`, `worker1`, etc.
- Use `.railway.internal` suffix
- Case-sensitive

**Test connectivity**:
```bash
# From one service's shell
ping coordinator.railway.internal
nc -zv worker1.railway.internal 5432
```

### Volume Issues

**Volume not persisting**:
- Check mount path: `/var/lib/postgresql/data`
- Verify volume is attached in Railway dashboard
- Check PGDATA environment variable

---

## Getting Help

### Check Service Logs

Always start with logs:
1. Railway dashboard → Service → View Logs
2. Look for ERROR, FATAL, or WARNING messages
3. Note the timestamp and context

### Useful Diagnostic Queries

```sql
-- Cluster overview
SELECT * FROM citus_get_active_worker_nodes();
SELECT * FROM citus_tables;

-- Performance
SELECT * FROM pg_stat_activity WHERE state = 'active';
SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;

-- Disk usage
SELECT pg_size_pretty(pg_database_size('postgres'));

-- Connections
SELECT count(*) FROM pg_stat_activity;
```

### Still Stuck?

1. **Check the README.md** for common issues
2. **Review SCALING.md** for scaling-related problems
3. **Search Citus documentation**: https://docs.citusdata.com
4. **Railway Discord**: https://discord.gg/railway
5. **Citus Community Slack**: https://www.citusdata.com/slack
6. **Open GitHub issue** in the template repository

### Reporting Issues

When reporting problems, include:
- ✅ Railway service logs
- ✅ PostgreSQL version: `SELECT version();`
- ✅ Citus version: `SELECT citus_version();`
- ✅ Query that's failing (if applicable)
- ✅ Error message (exact text)
- ✅ Steps to reproduce

---

## Prevention Tips

To avoid common issues:

✅ **Test in staging first** before scaling production  
✅ **Monitor metrics regularly** in Railway dashboard  
✅ **Keep backups** before major changes  
✅ **Document your setup** and customizations  
✅ **Follow scaling best practices** in SCALING.md  
✅ **Use proper distribution columns** (high cardinality)  
✅ **Index frequently queried columns**  
✅ **Keep Citus version updated**  
✅ **Review logs periodically** for warnings  
✅ **Plan maintenance windows** for rebalancing  

---

**Quick Links:**
- [Main README](README.md)
- [Scaling Guide](SCALING.md)
- [Citus Documentation](https://docs.citusdata.com/)
- [Railway Documentation](https://docs.railway.app/)