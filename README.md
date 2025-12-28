### Setup

#### Basic Server Actions

1. Build containers

    ```bash
        # Build images (if you change something in yml config)
        docker compose -f mc-server.yml build

        # Selective Build
        docker compose build mc-backup
    ```

2. Start / stop containers

    ```bash
        # Start services
        docker compose -f mc-server.yml up -d

        # Stop services
        docker compose -f mc-server.yml down

        # Restart all containers
        docker compose -f mc-server.yml restart

        # Selective restart (what we usually want)
        docker compose -f mc-server.yml up -d mc mc-backup
    ```

#### Backup and Restore

1. Trigger backup now

    ```bash
        docker exec mc-backup backup now
    ```

2. Restore backups (interactive)

    ```bash
        # Stop the server container:
        docker compose -f mc-server.yml stop mc

        # Run restore interactively
        docker compose -f mc-server.yml run --rm mc-restore

        # Start the server again:
        docker compose -f mc-server.yml start mc
    ```

#### Manual Restore From Google Drive

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