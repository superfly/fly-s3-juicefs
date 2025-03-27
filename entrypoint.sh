#!/bin/bash
set -e

# Fixed paths instead of environment variables
METADATA_PATH="/var/lib/juicefs/juicefs.db"
MOUNT_POINT="/data"
JUICEFS_VOLUME_NAME="juicefs"
CACHE_DIR="/dev/fly_vol/cache"

# Enable debug mode to see more information
set -x

# Ensure directories exist
mkdir -p $(dirname $METADATA_PATH)
mkdir -p $MOUNT_POINT
mkdir -p $CACHE_DIR

# Check if the cache filesystem is mounted
if ! grep -q "/dev/fly_vol" /proc/mounts; then
    echo "ERROR: /dev/fly_vol is not mounted. Cannot use for cache."
    exit 1
fi

# Display JuiceFS version
juicefs --version

# Start Litestream replication
echo "Starting Litestream replication..."
litestream replicate -config /etc/litestream/litestream.yml &
LITESTREAM_PID=$!

# Function to handle shutdown
function cleanup {
    echo "Shutting down..."
    
    # Unmount JuiceFS if mounted
    if mount | grep -q "$MOUNT_POINT"; then
        echo "Unmounting JuiceFS..."
        umount $MOUNT_POINT || true
    fi
    
    # Stop Litestream gracefully
    if ps -p $LITESTREAM_PID > /dev/null; then
        echo "Stopping Litestream..."
        kill -SIGTERM $LITESTREAM_PID || true
        # Wait for Litestream to finish
        wait $LITESTREAM_PID 2>/dev/null || true
    fi
    
    exit 0
}

# Register cleanup on exit
trap cleanup SIGINT SIGTERM

# If metadata DB doesn't exist, check if we need to restore from S3
if [ ! -f "$METADATA_PATH" ] && [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ] && [ -n "$BUCKET_NAME" ]; then
    echo "Metadata DB doesn't exist. Attempting to restore from S3..."
    mkdir -p $(dirname $METADATA_PATH)
    
    # Try to restore from S3
    if litestream restore -config /etc/litestream/litestream.yml -if-replica-exists -o $METADATA_PATH $METADATA_PATH; then
        echo "Successfully restored metadata from S3"
    else
        echo "No existing replica found or restore failed. Will create a new metadata DB."
        touch $METADATA_PATH  # Ensure the file exists for Litestream to track
    fi
fi

# Format the filesystem if it doesn't exist
if ! juicefs status "sqlite3://$METADATA_PATH" &>/dev/null; then
    echo "Formatting JuiceFS volume..."
    
    # Check if S3 credentials are available
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$BUCKET_NAME" ]; then
        echo "WARNING: S3 credentials or bucket name not set. Cannot use S3 storage."
        exit 1
    fi
    
    # Unset any endpoint URL to avoid issues
    unset AWS_ENDPOINT_URL_S3
    
    echo "Using S3 bucket: $BUCKET_NAME"
    
    # Simplest possible formatting command
    juicefs format \
        --storage s3 \
        --bucket "$BUCKET_NAME" \
        --access-key "$AWS_ACCESS_KEY_ID" \
        --secret-key "$AWS_SECRET_ACCESS_KEY" \
        --trash-days 0 \
        "sqlite3://$METADATA_PATH" "$JUICEFS_VOLUME_NAME"
    
    echo "JuiceFS volume formatted successfully"
fi

# Mount the filesystem with minimal options
echo "Mounting JuiceFS..."

# Mount JuiceFS with only essential parameters
juicefs mount --cache-dir $CACHE_DIR "sqlite3://$METADATA_PATH" "$MOUNT_POINT" &

JUICEFS_PID=$!

# Wait for mount to be ready
sleep 2

# Check if mount was successful
if ! mount | grep -q "$MOUNT_POINT"; then
    echo "ERROR: Failed to mount JuiceFS"
    cleanup
    exit 1
fi

echo "JuiceFS mounted successfully at $MOUNT_POINT"
echo "Using persistent cache at $CACHE_DIR"
echo "SQLite metadata at $METADATA_PATH is being replicated to S3"

# Disable debug mode
set +x

# Hang and wait for signals
wait $JUICEFS_PID 