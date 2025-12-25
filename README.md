### Setup

#### Basic Server Actions

```bash
# Build images (if you change something in yml config)
docker compose -f mc-server.yml build

# Selective Build
docker compose build mc-backup

```

```bash
# Start services
docker compose -f mc-server.yml up -d

# Stop services
docker compose -f mc-server.yml down

# Restart all containers
docker compose -f mc-server.yml restart

# Selective restart
docker compose -f mc-server.yml restart mc
```

#### Manaul Backup and Restore

1. Trigger backup now

    ```bash
        docker exec mc-backup backup now
    ```
2. List backups

    ```bash
        docker exec mc-backup ls -lh /backups
    ```

#### Restore From Google Drive

```bash
# Stop everything
docker compose -f mc-server.yml down

# Download backup from Drive
rclone copy gdrive:mc-backups ./restore

# Extract backup
tar -xzf restore/minecraft-YYYY-MM-DD_HH-MM-SS.tar.gz -C ./data

# Restart
docker compose -f mc-server.yml up -d
```