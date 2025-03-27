# JuiceFS on Fly.io with S3 Storage and Litestream Metadata Backup

This project sets up JuiceFS on Fly.io using S3-compatible storage for file data and a local SQLite database for metadata, which is replicated to S3 using Litestream for durability.

## Architecture

- **Data Storage**: S3-compatible storage (specified by `BUCKET_NAME`)
- **Metadata**: SQLite database stored at `/var/lib/juicefs/juicefs.db`
- **Metadata Backup**: Litestream replicating SQLite to S3 at `/dev/fly_vol/juicefs.db`
- **Cache Storage**: Local volume at `/dev/fly_vol/cache`
- **Mount Point**: JuiceFS is mounted at `/data`
- **JuiceFS Version**: 1.2.3

## Prerequisites

- [Fly.io account](https://fly.io)
- [flyctl installed](https://fly.io/docs/hands-on/install-flyctl/)
- S3-compatible storage service
- Tigris Storage account (or other S3-compatible storage for Litestream)

## Setup

1. Create a Fly volume to store the cache and metadata:

```bash
fly volumes create juicefs_data --size 25 --region dfw
```

2. Add the required secrets for S3 access:

```bash
fly secrets set \
  AWS_ACCESS_KEY_ID="your-s3-access-key" \
  AWS_SECRET_ACCESS_KEY="your-s3-secret-key" \
  BUCKET_NAME="your-s3-bucket-name" \
  AWS_REGION="your-s3-region"
```

3. Deploy the application:

```bash
fly deploy
```

## How It Works

### JuiceFS Configuration

JuiceFS combines a metadata engine (SQLite in this case) with a data storage backend (S3). The system:

- Uses S3 storage for the actual file data
- Stores metadata in a local SQLite database
- Maintains cache on the local Fly volume
- Mounts the filesystem at `/data`

### Metadata Management with Litestream

Litestream continuously replicates the SQLite database to S3:

- The metadata database is stored at `/var/lib/juicefs/juicefs.db`
- Litestream stores the metadata in S3 at the path defined in `/etc/litestream/litestream.yml`
- Database backup location: `/dev/fly_vol/juicefs.db`
- Replication frequency: Every 1 second (defined in Litestream config)
- On container start, it attempts to restore from S3 if needed

### Key File Paths

This deployment uses the following key paths:

- **JuiceFS Metadata**: `/var/lib/juicefs/juicefs.db`
- **Litestream Database Path**: `/dev/fly_vol/juicefs.db`
- **JuiceFS Mount Point**: `/data`
- **Cache Directory**: `/dev/fly_vol/cache`
- **Litestream Config**: `/etc/litestream/litestream.yml`

## Usage

After deployment, JuiceFS will be mounted at `/data`. You can store and access files at this location.

To check the status of your JuiceFS instance:

```bash
fly ssh console -C "juicefs status sqlite3:///var/lib/juicefs/juicefs.db"
```

To view disk usage statistics:

```bash
fly ssh console -C "juicefs stats sqlite3:///var/lib/juicefs/juicefs.db"
```

To verify the Litestream replication:

```bash
fly ssh console -C "litestream generations -config /etc/litestream/litestream.yml"
```

## Disaster Recovery

If your Fly Machine is destroyed, the system will:

1. Create a new machine
2. Attach the same Fly volume
3. Attempt to restore the SQLite metadata from S3 using Litestream
4. Format JuiceFS with S3 storage if it doesn't exist
5. Mount JuiceFS with the restored metadata

This provides resilience against machine failures while keeping both your data and metadata intact.

## Performance Testing

The repository includes two benchmark scripts:

- `juicefs_benchmark.sh`: Comprehensive benchmark of JuiceFS performance
- `juicefs_simple_benchmark.sh`: Quick performance test for basic validation

To run a benchmark:

```bash
fly ssh console -C "/usr/local/bin/juicefs_simple_benchmark.sh"
```

## Troubleshooting

Check container logs:

```bash
fly logs
```

Access shell in the container:

```bash
fly ssh console
```

View JuiceFS debug information:

```bash
fly ssh console -C "juicefs --version"
fly ssh console -C "ls -la /data"
fly ssh console -C "df -h | grep juicefs"
```

## Important Notes

- JuiceFS uses S3 for data storage and local SQLite for metadata
- Metadata is periodically backed up to S3 using Litestream
- The SQLite file size grows with the number of files, not their size
- Cache is stored on the local Fly volume at `/dev/fly_vol/cache`
- This setup does not use environment variables for paths but instead uses hardcoded paths in the entrypoint script

## Repository

This project is maintained in the [superfly/fly-s3-juicefs](https://github.com/superfly/fly-s3-juicefs) repository.

### Repository Structure

- `Dockerfile`: Sets up Ubuntu with JuiceFS 1.2.3 and Litestream
- `entrypoint.sh`: Main script that handles metadata restoration, JuiceFS formatting, and mounting
- `litestream.yml`: Configuration for Litestream replication to S3
- `juicefs_benchmark.sh`: Script for comprehensive performance testing
- `juicefs_simple_benchmark.sh`: Script for quick performance validation
- `fly.toml`: Fly.io application configuration

### Contributing

Contributions to improve this JuiceFS integration are welcome! Please submit issues and pull requests on the GitHub repository.

## License

This project is available under the MIT License. 