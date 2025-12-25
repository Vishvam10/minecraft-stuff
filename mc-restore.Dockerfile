# Base image
FROM itzg/mc-backup:latest

# Override entrypoint
ENTRYPOINT ["/restore-notify.sh"]