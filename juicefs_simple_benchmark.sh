#!/bin/bash
set -e

# Default location if no argument is passed
DEFAULT_TEST_DIR="/data"

# Check for command-line argument
if [ -n "$1" ]; then
    TEST_DIR="$1"
    echo "Using provided test directory: $TEST_DIR"
else
    TEST_DIR="$DEFAULT_TEST_DIR"
    echo "Using default test directory: $TEST_DIR"
fi

# Ensure the test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo "ERROR: Test directory $TEST_DIR does not exist. Please provide a valid directory."
    exit 1
fi

# Create test file path
TEST_FILE="$TEST_DIR/benchmark_test_file"

# Print system info
echo "========== System Information =========="
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Kernel: $(uname -r)"
echo "Mount Info for $TEST_DIR: $(df -h $TEST_DIR | tail -1)"
echo "Filesystem Type: $(stat -fc %T $TEST_DIR)"

# If it's a JuiceFS mount, get additional information
if mount | grep -q "juicefs.*$TEST_DIR"; then
    echo "JuiceFS Version: $(juicefs --version 2>&1 | head -1)"
    echo "JuiceFS Mount Info: $(mount | grep juicefs | grep $TEST_DIR)"
    echo "Cache Settings: $(cat /proc/mounts | grep juicefs | grep -o 'cache-size=[0-9]*')"
    JUICEFS_DIR=true
else
    echo "Not a JuiceFS mount, standard filesystem benchmarks will be performed."
    JUICEFS_DIR=false
fi
echo ""

# Direct I/O Performance Test using dd
echo "========== Direct I/O Performance Test for $TEST_DIR =========="

# Write test with direct I/O
echo "Direct sequential write test (4K blocks):"
dd if=/dev/zero of=$TEST_FILE bs=4K count=10000 oflag=direct conv=fsync 2>&1 | grep -v records

# Write test with 1M blocks
echo "Direct sequential write test (1M blocks):"
dd if=/dev/zero of=$TEST_FILE bs=1M count=1000 oflag=direct conv=fsync 2>&1 | grep -v records

# Read test with direct I/O
echo "Direct sequential read test (4K blocks):"
dd if=$TEST_FILE of=/dev/null bs=4K count=10000 iflag=direct 2>&1 | grep -v records

# Read test with 1M blocks
echo "Direct sequential read test (1M blocks):"
dd if=$TEST_FILE of=/dev/null bs=1M count=1000 iflag=direct 2>&1 | grep -v records

# Clean up
rm -f $TEST_FILE

# Quick filesystem operations test
echo ""
echo "========== Filesystem Operations Test for $TEST_DIR =========="

# Create and remove small files test
echo "Creating and removing 1000 empty files:"
time for i in $(seq 1 1000); do
    touch "$TEST_DIR/smallfile_$i"
done

time for i in $(seq 1 1000); do
    rm "$TEST_DIR/smallfile_$i"
done

# Check current stats from JuiceFS if applicable
if [ "$JUICEFS_DIR" = true ]; then
    echo ""
    echo "========== JuiceFS Stats =========="
    juicefs status sqlite3:///var/lib/juicefs/juicefs.db
fi

echo ""
echo "========== Benchmark Complete =========="
echo "Results summary for $TEST_DIR:"
echo "- Check the output above for detailed performance metrics"
echo "- Remember that these numbers are influenced by caching, filesystem type, and underlying storage" 