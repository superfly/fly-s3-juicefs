FROM ubuntu:22.04

# Set noninteractive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    fuse \
    ca-certificates \
    tzdata \
    procps \
    sqlite3 \
    bc \
    fio \
    iotop \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install JuiceFS (latest stable version)
RUN wget -O /tmp/juicefs.tar.gz https://github.com/juicedata/juicefs/releases/download/v1.2.3/juicefs-1.2.3-linux-amd64.tar.gz \
    && tar -zxf /tmp/juicefs.tar.gz -C /tmp \
    && mv /tmp/juicefs /usr/local/bin/ \
    && chmod +x /usr/local/bin/juicefs \
    && rm /tmp/juicefs.tar.gz

# Install Litestream
RUN wget -O /tmp/litestream.tar.gz https://github.com/benbjohnson/litestream/releases/download/v0.3.11/litestream-v0.3.11-linux-amd64.tar.gz \
    && tar -xzf /tmp/litestream.tar.gz -C /tmp \
    && mv /tmp/litestream /usr/local/bin/ \
    && chmod +x /usr/local/bin/litestream \
    && rm /tmp/litestream.tar.gz

# Create necessary directories
RUN mkdir -p /data /var/lib/juicefs /etc/litestream

# Add configuration files
COPY litestream.yml /etc/litestream/litestream.yml

# Add entrypoint script and benchmark script
COPY entrypoint.sh /entrypoint.sh
COPY juicefs_benchmark.sh /usr/local/bin/juicefs_benchmark.sh
COPY juicefs_simple_benchmark.sh /usr/local/bin/juicefs_simple_benchmark.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/juicefs_benchmark.sh /usr/local/bin/juicefs_simple_benchmark.sh

# Set working directory
WORKDIR /app

# Expose port (adjust as needed for your application)
EXPOSE 8080

# Set default command
ENTRYPOINT ["/entrypoint.sh"] 
#CMD ["tail -f /dev/null"]