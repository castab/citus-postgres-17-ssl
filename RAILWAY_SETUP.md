# Railway Template Setup Guide

This guide walks you through creating a Railway template for your Citus cluster.

## Repository Structure

Create a GitHub repository with the following structure:

```
citus-railway-template/
├── README.md                      # User-facing documentation
├── RAILWAY_SETUP.md              # This file
├── coordinator/
│   ├── Dockerfile
│   ├── init-coordinator.sh
│   └── railway.json
├── worker/
│   ├── Dockerfile
│   └── railway.json
├── registrar/
│   ├── Dockerfile
│   ├── register-workers.sh
│   └── railway.json
└── .gitignore
```

## Step-by-Step Setup

### 1. Create GitHub Repository

1. Create a new public GitHub repository named `citus-railway-template`
2. Add all files from this artifact structure
3. Commit and push to main branch

### 2. Create Railway Template

1. Go to Railway Dashboard → Your Workspace Settings → Templates
2. Click "New Template"
3. Give it a name: "Citus Distributed PostgreSQL"
4. Add a description: "Production-ready Citus cluster with 1 coordinator and 2 workers"

### 3. Add Services

#### Service 1: Coordinator

1. Click "Add Service" → "GitHub Repo"
2. Select your `citus-railway-template` repository
3. Configure:
   - **Service Name**: `coordinator`
   - **Root Directory**: `coordinator`
   - **Dockerfile Path**: `coordinator/Dockerfile`

4. Add Environment Variables:
   ```
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=${{ secret(32) }}
   POSTGRES_DB=postgres
   PGDATA=/var/lib/postgresql/data/pgdata
   ```

5. Add Volume:
   - Mount Path: `/var/lib/postgresql/data`

6. Enable Public Networking (users will connect here)

#### Service 2: Worker 1

1. Click "Add Service" → "GitHub Repo"
2. Select same repository
3. Configure:
   - **Service Name**: `worker1`
   - **Root Directory**: `worker`
   - **Dockerfile Path**: `worker/Dockerfile`

4. Add Environment Variables:
   ```
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=${{ coordinator.POSTGRES_PASSWORD }}
   POSTGRES_DB=postgres
   PGDATA=/var/lib/postgresql/data/pgdata
   ```

5. Add Volume:
   - Mount Path: `/var/lib/postgresql/data`

6. Keep Private (no public networking needed)

#### Service 3: Worker 2

1. Click "Add Service" → "GitHub Repo"
2. Select same repository
3. Configure:
   - **Service Name**: `worker2`
   - **Root Directory**: `worker`
   - **Dockerfile Path**: `worker/Dockerfile`

4. Add Environment Variables (same as worker1):
   ```
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=${{ coordinator.POSTGRES_PASSWORD }}
   POSTGRES_DB=postgres
   PGDATA=/var/lib/postgresql/data/pgdata
   ```

5. Add Volume:
   - Mount Path: `/var/lib/postgresql/data`

6. Keep Private

#### Service 4: Worker Registrar

1. Click "Add Service" → "GitHub Repo"
2. Select same repository
3. Configure:
   - **Service Name**: `registrar`
   - **Root Directory**: `registrar`
   - **Dockerfile Path**: `registrar/Dockerfile`

4. Add Environment Variables:
   ```
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=${{ coordinator.POSTGRES_PASSWORD }}
   COORDINATOR_HOST=coordinator.railway.internal
   ```

5. No volume needed (ephemeral service)

6. This service will run once and exit

### 4. Configure Service Dependencies

Set up the correct startup order:

1. `coordinator` starts first (no dependencies)
2. `worker1` and `worker2` start after coordinator (depends on coordinator)
3. `registrar` starts last (depends on coordinator, worker1, worker2)

### 5. Add Shared Variables

Create shared variables accessible to all services:

1. Go to Project Settings → Shared Variables
2. Add:
   ```
   DATABASE_URL=postgresql://${{ coordinator.POSTGRES_USER }}:${{ coordinator.POSTGRES_PASSWORD }}@coordinator.railway.internal:5432/${{ coordinator.POSTGRES_DB }}
   ```

### 6. Template Metadata

Add these details to your template:

- **Category**: Databases
- **Tags**: postgres, citus, distributed, database, postgresql
- **Icon**: Use the PostgreSQL or Citus logo
- **Demo/Example**: Link to Citus documentation

### 7. Template README

Your README.md should include:

✅ Clear description of what Citus is  
✅ Use cases and benefits  
✅ Architecture diagram (ASCII or image)  
✅ Quick start guide  
✅ Example queries  
✅ Scaling instructions  
✅ Environment variables reference  
✅ Troubleshooting tips  
✅ Links to Citus documentation  

### 8. Test Your Template

Before publishing:

1. Deploy the template to your own Railway account
2. Verify all services start correctly
3. Check that workers are registered:
   ```sql
   SELECT * FROM citus_get_active_worker_nodes();
   ```
4. Test creating a distributed table
5. Verify data distribution across workers

### 9. Publish Template

1. Review all settings one final time
2. Click "Publish Template"
3. Choose visibility: Public (for marketplace)
4. Submit for review (if applicable)

## Railway-Specific Variables

Railway provides these special variables you can use:

- `${{ SERVICE_NAME.VARIABLE }}` - Reference another service's variable
- `${{ secret(length) }}` - Generate random secret
- `${{ RAILWAY_PUBLIC_DOMAIN }}` - Public URL of service
- `${{ SERVICE_NAME.RAILWAY_PRIVATE_DOMAIN }}` - Private network address

## Private Networking

Railway automatically sets up private networking:

- Services communicate via `service-name.railway.internal`
- Only expose the coordinator publicly
- Workers stay on private network
- Lower latency and no egress costs

## Volume Persistence

Each service needs persistent storage:

- Coordinator: `/var/lib/postgresql/data`
- Worker 1: `/var/lib/postgresql/data`
- Worker 2: `/var/lib/postgresql/data`

Railway automatically handles volume lifecycle.

## Scaling Considerations

**Adding Workers**: 
- Users can duplicate the worker service
- Update registrar to discover new workers
- Or manually register via SQL

**Vertical Scaling**:
- Users adjust CPU/RAM per service
- Recommended: Coordinator gets most resources

**Removing Workers**:
- Requires manual intervention
- Must rebalance shards before removal

## Monetization

Once published to marketplace:
- Earn 50% kickback on usage
- Paid out in Railway credits or cash
- Template must be public and follow TOS

## Template Updates

When you update your repository:
- Railway detects changes on main branch
- Users get notification of available updates
- They can choose when to apply updates

## Best Practices

✅ Use Railway template variables for secrets  
✅ Document all environment variables  
✅ Include health checks where possible  
✅ Keep Dockerfiles minimal and cached  
✅ Test thoroughly before publishing  
✅ Keep README comprehensive  
✅ Use semantic versioning for updates  
✅ Include troubleshooting section  

## Support & Kickback

To be eligible for template kickback:
- Template must be in marketplace
- Must follow Railway's Fair Use Policy
- Must abide by Terms of Service

Kickback rate: 50% of usage costs from template deployments

## Common Issues

**Workers not registering**:
- Check that coordinator is fully initialized
- Verify private network connectivity
- Check registrar service logs

**Connection refused**:
- Ensure pg_hba.conf allows private network ranges
- Check that services use `.railway.internal` domains

**Slow startup**:
- First deploy takes longer (image pull + build)
- Subsequent deploys are faster with caching

## Additional Resources

- [Railway Template Docs](https://docs.railway.com/reference/templates)
- [Railway Variables Guide](https://docs.railway.com/reference/variables)
- [Citus Documentation](https://docs.citusdata.com/)
- [Railway Discord](https://discord.gg/railway) - Get help from community

## Next Steps After Template Creation

1. ⭐ Star your template repository
2. 📝 Write a blog post about it
3. 🐦 Share on social media
4. 💬 Announce in Railway Discord
5. 📊 Monitor usage and kickback earnings
6. 🔄 Keep template updated with Citus releases