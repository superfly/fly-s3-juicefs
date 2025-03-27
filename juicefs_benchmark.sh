#!/bin/bash
set -e

# Configuration
TEST_DIR="/data/benchmark"
FILE_SIZE_MB=1000  # Size of test file in MB
BLOCK_SIZE_KB=1024  # Block size for I/O operations in KB
NUM_FILES=100      # Number of small files for metadata testing
SMALL_FILE_SIZE_KB=100  # Size of small files in KB

# Ensure the test directory exists
mkdir -p $TEST_DIR
cd $TEST_DIR

echo "==== JuiceFS Performance Benchmark ===="
echo "Mount point: /data"
echo "Test directory: $TEST_DIR"
echo "Test file size: ${FILE_SIZE_MB}MB"
echo "Block size: ${BLOCK_SIZE_KB}KB"
echo "Date: $(date)"
echo "=======================================\n"

# Function to clean up test files
cleanup() {
    echo "Cleaning up test files..."
    rm -rf $TEST_DIR/*
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# System information
echo "=== System Information ==="
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d ':' -f 2 | sed 's/^[ \t]*//')"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Disk: $(df -h /data | tail -1 | awk '{print $2 " total, " $4 " available"}')"
echo "Kernel: $(uname -r)"
echo "JuiceFS version: $(juicefs --version | head -1)"
echo ""

# Check JuiceFS status
echo "=== JuiceFS Status ==="
echo "Mount information:"
mount | grep juicefs
echo ""
echo "JuiceFS status:"
juicefs status sqlite3:///var/lib/juicefs/juicefs.db || echo "Could not retrieve JuiceFS status"
echo ""

# Sequential write test
echo "=== Sequential Write Test ==="
echo "Writing a ${FILE_SIZE_MB}MB file with ${BLOCK_SIZE_KB}KB blocks..."
dd if=/dev/zero of=${TEST_DIR}/test_write bs=${BLOCK_SIZE_KB}K count=$((FILE_SIZE_MB*1024/BLOCK_SIZE_KB)) conv=fsync 2>&1
echo ""

# Sequential read test
echo "=== Sequential Read Test ==="
echo "Reading the ${FILE_SIZE_MB}MB file with ${BLOCK_SIZE_KB}KB blocks..."
# Drop caches if running as root
[ "$(id -u)" = "0" ] && echo 3 > /proc/sys/vm/drop_caches
dd if=${TEST_DIR}/test_write of=/dev/null bs=${BLOCK_SIZE_KB}K count=$((FILE_SIZE_MB*1024/BLOCK_SIZE_KB)) 2>&1
echo ""

# Random read/write test using fio if available
if command -v fio &> /dev/null; then
    echo "=== Random I/O Test (fio) ==="
    
    echo "Random write test (4KB blocks)..."
    fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=4k --size=1G --numjobs=1 --runtime=60 --time_based --end_fsync=1 --filename=${TEST_DIR}/fio_test_file --direct=1
    
    echo "Random read test (4KB blocks)..."
    [ "$(id -u)" = "0" ] && echo 3 > /proc/sys/vm/drop_caches
    fio --name=random-read --ioengine=posixaio --rw=randread --bs=4k --size=1G --numjobs=1 --runtime=60 --time_based --filename=${TEST_DIR}/fio_test_file --direct=1
    
    echo "Mixed random read/write test (70% read, 30% write)..."
    fio --name=mixed-rw --ioengine=posixaio --rw=randrw --bs=4k --size=1G --numjobs=1 --runtime=60 --time_based --rwmixread=70 --filename=${TEST_DIR}/fio_test_file --direct=1
else
    echo "fio not available, skipping random I/O tests"
fi

# Metadata performance test (creating and reading many small files)
echo "=== Metadata Performance Test ==="
echo "Creating $NUM_FILES small files (${SMALL_FILE_SIZE_KB}KB each)..."
START_TIME=$(date +%s.%N)
for i in $(seq 1 $NUM_FILES); do
    dd if=/dev/zero of=${TEST_DIR}/small_file_$i bs=1K count=$SMALL_FILE_SIZE_KB &> /dev/null
done
END_TIME=$(date +%s.%N)
CREATE_TIME=$(echo "$END_TIME - $START_TIME" | bc)
echo "Time to create $NUM_FILES files: $CREATE_TIME seconds"
echo "Files created per second: $(echo "$NUM_FILES / $CREATE_TIME" | bc)"

echo "Listing $NUM_FILES small files..."
START_TIME=$(date +%s.%N)
ls -la ${TEST_DIR}/small_file_* > /dev/null
END_TIME=$(date +%s.%N)
LIST_TIME=$(echo "$END_TIME - $START_TIME" | bc)
echo "Time to list $NUM_FILES files: $LIST_TIME seconds"
echo ""

# Reading small files
echo "Reading $NUM_FILES small files..."
START_TIME=$(date +%s.%N)
for i in $(seq 1 $NUM_FILES); do
    cat ${TEST_DIR}/small_file_$i > /dev/null
done
END_TIME=$(date +%s.%N)
READ_TIME=$(echo "$END_TIME - $START_TIME" | bc)
echo "Time to read $NUM_FILES files: $READ_TIME seconds"
echo "Files read per second: $(echo "$NUM_FILES / $READ_TIME" | bc)"
echo ""

# Cleanup
cleanup

echo "Benchmark complete!"
echo "For a more comprehensive benchmark, consider using fio or iozone tools." 