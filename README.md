# JuiceFS on Fly.io with Raw Block Device and Litestream

This project sets up JuiceFS on Fly.io using a raw block device volume with SQLite for metadata storage and Litestream for S3 backup.

## Architecture

- **Data Storage**: Raw block device on Fly.io (25GB volume)
- **Metadata**: SQLite database stored at `/var/lib/juicefs/juicefs.db`
- **Metadata Backup**: Litestream replicating SQLite to S3
- **Mount Point**: JuiceFS is mounted at `/data`

## Prerequisites

- [Fly.io account](https://fly.io)
- [flyctl installed](https://fly.io/docs/hands-on/install-flyctl/)
- S3-compatible storage for metadata backup

## Setup

1. Create a raw volume on Fly.io:

```bash
curl -X POST "https://api.machines.dev/v1/apps/kurt-juicefs/volumes" \
  -H "Authorization: Bearer $(fly auth token)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "juice_data",
    "size_gb": 25,
    "fstype": "raw",
    "region": "ord"
  }'
```

2. Add the required S3 secrets:

```bash
fly secrets set AWS_ACCESS_KEY_ID="your-access-key" \
  AWS_SECRET_ACCESS_KEY="your-secret-key" \
  AWS_ENDPOINT_URL_S3="your-s3-endpoint" \
  AWS_REGION="your-region" \
  BUCKET_NAME="your-bucket-name"
```

3. Deploy the application:

```bash
fly deploy
```

## How It Works

### JuiceFS

JuiceFS combines a metadata engine (SQLite in this case) with a data storage backend (raw block device). The filesystem is mounted at `/data`.

### Metadata Management with Litestream

Litestream continuously replicates the SQLite database to S3:

- The database is stored at `/var/lib/juicefs/juicefs.db`
- Litestream writes WAL files to S3 every 10 seconds
- On container start, it attempts to restore from S3 if needed

### Hardcoded Paths

This deployment uses fixed paths instead of environment variables:

- Block Device: `/dev/vdb`
- Metadata Path: `/var/lib/juicefs/juicefs.db`
- Mount Point: `/data`
- Cache Directory: `/var/lib/juicefs/cache`

## Usage

After deployment, JuiceFS will be mounted at `/data`. You can store and access files at this location.

To check the status of your JuiceFS instance:

```bash
fly ssh console -C "juicefs status sqlite3:///var/lib/juicefs/juicefs.db"
```

To verify the Litestream replication:

```bash
fly ssh console -C "litestream generations"
```

## Disaster Recovery

If your Fly Machine is destroyed, the system will:

1. Create a new machine
2. Attach the same raw block device volume
3. Attempt to restore the SQLite metadata from S3
4. Mount JuiceFS with the restored metadata

This provides resilience against machine failures while keeping your data intact.

## Troubleshooting

Check container logs:

```bash
fly logs
```

Access shell in the container:

```bash
fly ssh console
```

## Important Notes

- The raw volume is attached as a block device to the Fly Machine
- JuiceFS uses this raw block device for data storage
- Your metadata is stored in SQLite and replicated to S3
- The SQLite file size grows with the number of files, not their size 