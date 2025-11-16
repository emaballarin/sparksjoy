# OpenWebUI Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

- [Service Issues](#service-issues)
- [Network & Connectivity](#network--connectivity)
- [Authentication Problems](#authentication-problems)
- [Configuration Validation Errors](#configuration-validation-errors)
- [Provider Integration](#provider-integration)
- [Performance Issues](#performance-issues)
- [Data & Storage](#data--storage)
- [TLS/HTTPS Issues](#tlshttps-issues)
- [Docker Issues](#docker-issues)
- [Automatic Updates (Watchtower)](#automatic-updates-watchtower)

---

## Service Issues

### Containers won't start

**Symptoms**: `docker compose up -d` fails or containers exit immediately

**Solutions**:

1. Check logs for specific errors:

```bash
docker compose logs openwebui
docker compose logs traefik
```

2. Verify `.env` file exists and is valid:

```bash
cat .env | grep WEBUI_SECRET_KEY
```

3. Check port conflicts:

```bash
# Check if port is already in use
sudo netstat -tulpn | grep -E ':8443'

# Or on macOS
lsof -i :8443
```

4. Remove and recreate:

```bash
docker compose down -v
docker compose up -d
```

### Service unhealthy

**Symptoms**: `docker compose ps` shows "unhealthy" status

**Solutions**:

1. Wait for startup (can take 60+ seconds):

```bash
# Watch health status
watch docker compose ps
```

2. Check health check status:

```bash
# Container health status
docker compose ps
docker inspect --format='{{.State.Health.Status}}' owui-openwebui
```

3. Increase health check timeouts in `docker-compose.yml`:

```yaml
healthcheck:
    start_period: 120s # Increase from 60s
```

### Service keeps restarting

**Symptoms**: Container repeatedly starts and stops

**Solutions**:

1. Check for memory issues:

```bash
# View resource usage
docker stats

# Increase memory limit in .env
OPENWEBUI_MEMORY_LIMIT=8g
```

2. Check for configuration errors:

```bash
docker compose logs --tail=100 openwebui
```

3. Validate configuration:

```bash
docker compose config
```

---

## Network & Connectivity

### Can't access OpenWebUI at https://localhost:8443

**Solutions**:

1. Verify Traefik is running:

```bash
docker compose ps traefik
docker compose logs traefik
```

2. Check Traefik configuration:

```bash
# View Traefik logs for routing errors
docker compose logs traefik | grep -i error
```

3. Check firewall rules:

```bash
# Linux
sudo ufw status
sudo ufw allow 8443/tcp

# macOS
# System Preferences → Security & Privacy → Firewall Options
```

### WebSocket connection failures

**Symptoms**: "WebSocket connection failed" errors in browser console

**Solutions**:

1. Verify `CORS_ALLOW_ORIGIN` in `.env`:

```bash
CORS_ALLOW_ORIGIN=https://localhost:8443
```

2. Check browser developer console for specific errors

3. Ensure Traefik WebSocket support (already configured in provided setup)

4. Try disabling browser extensions that might block WebSockets

### Can't connect to external Ollama

**Symptoms**: Ollama models don't appear, connection errors

**Solutions**:

1. Verify Ollama is running on host:

```bash
curl http://localhost:11434/api/tags
```

2. Test connection from container:

```bash
docker compose exec openwebui curl http://host.docker.internal:11434/api/tags
```

3. Check `OLLAMA_BASE_URL` in `.env`:

```bash
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

4. For Linux, ensure `host.docker.internal` resolves:

```bash
# Add to docker-compose.yml if missing
extra_hosts:
  - "host.docker.internal:host-gateway"
```

5. Restart OpenWebUI:

```bash
docker compose restart openwebui
```

### Network isolation issues

**Symptoms**: Services can't communicate

**Solutions**:

1. Check network exists:

```bash
docker network ls | grep owui-network
```

2. Verify containers are on the network:

```bash
docker network inspect owui-network
```

3. Recreate network:

```bash
docker compose down
docker network rm owui-network
docker compose up -d
```

---

## Authentication Problems

### Can't log in / Invalid credentials

**Solutions**:

1. Reset admin password (requires database access):

```bash
# Stop services
docker compose down

# Remove user database
rm volumes/data/webui.db

# Restart and create new admin
docker compose up -d
```

2. Check JWT configuration:

```bash
cat .env | grep -E '(WEBUI_SECRET_KEY|JWT_EXPIRES_IN)'
```

3. Clear browser cookies and try again

### Session expires too quickly

**Solutions**:

1. Increase `JWT_EXPIRES_IN` in `.env`:

```bash
JWT_EXPIRES_IN=30d
```

2. Restart OpenWebUI:

```bash
docker compose restart openwebui
```

### Can't create new users

**Symptoms**: Registration disabled or pending approval required

**Solutions**:

1. Enable signup in `.env`:

```bash
ENABLE_SIGNUP=true
DEFAULT_USER_ROLE=user
```

2. Approve pending users (admin account):
    - Login as admin
    - Settings → Users
    - Approve pending users

---

## Configuration Validation Errors

### Invalid WEBUI_SECRET_KEY

**Symptoms**: "WEBUI_SECRET_KEY is set to invalid default value" or "too short"

**Solutions**:

1. Run setup script to generate a secure key:

```bash
./scripts/setup.sh
```

2. Or manually generate and set in `.env`:

```bash
# Generate a secure key (minimum 32 characters)
openssl rand -base64 32

# Add to .env
WEBUI_SECRET_KEY=<generated-key>
```

3. Validate configuration:

```bash
./scripts/validate-config.sh
```

### CORS and URL mismatch

**Symptoms**: "CORS_ALLOW_ORIGIN and WEBUI_URL do not match"

**Solutions**:

1. Ensure both values match in `.env`:

```bash
WEBUI_URL=https://your-domain.com:8443
CORS_ALLOW_ORIGIN=https://your-domain.com:8443
```

2. Restart OpenWebUI:

```bash
docker compose restart openwebui
```

### JWT token format invalid

**Symptoms**: "JWT_EXPIRES_IN has invalid format"

**Solutions**:

1. Use valid time format in `.env`:

```bash
# Valid formats:
JWT_EXPIRES_IN=7d    # 7 days
JWT_EXPIRES_IN=4w    # 4 weeks
JWT_EXPIRES_IN=12h   # 12 hours
JWT_EXPIRES_IN=30m   # 30 minutes
JWT_EXPIRES_IN=60s   # 60 seconds
```

2. Restart OpenWebUI after changes

### Network subnet invalid

**Symptoms**: "NETWORK_SUBNET has invalid CIDR format"

**Solutions**:

1. Use proper CIDR notation in `.env`:

```bash
# Valid examples:
NETWORK_SUBNET=172.29.0.0/16
NETWORK_SUBNET=10.0.0.0/24
NETWORK_SUBNET=192.168.100.0/24
```

2. Recreate network:

```bash
docker compose down
docker network rm owui-network
docker compose up -d
```

### Backup encryption not configured

**Symptoms**: "Backup encryption is disabled" warning

**Solutions**:

1. Generate GPG key:

```bash
gpg --full-generate-key
```

2. Configure in `.env`:

```bash
BACKUP_ENABLE_ENCRYPTION=true
BACKUP_GPG_RECIPIENT=your-email@example.com
```

3. Test backup:

```bash
./scripts/backup.sh --encrypt
```

### Let's Encrypt email invalid

**Symptoms**: "LETSENCRYPT_EMAIL has invalid format"

**Solutions**:

1. Set valid email in `.env`:

```bash
LETSENCRYPT_EMAIL=admin@your-domain.com
```

2. Restart Traefik:

```bash
docker compose restart traefik
```

### Running validation

**Check all configuration:**

```bash
# Standard validation
./scripts/validate-config.sh

# Strict mode (fail on warnings)
./scripts/validate-config.sh --strict

# View health status
./scripts/health-check.sh --verbose
```

---

## Provider Integration

### OpenAI API errors

**Symptoms**: "Invalid API key" or "Rate limit exceeded"

**Solutions**:

1. Verify API key in `.env`:

```bash
cat .env | grep OPENAI_API_KEY
```

2. Test API key directly:

```bash
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

3. Check rate limits and billing at: https://platform.openai.com/account/usage

4. Restart OpenWebUI after changing key:

```bash
docker compose restart openwebui
```

### Custom provider not working

**Solutions**:

1. Verify base URL is correct:

```bash
OPENAI_API_BASE_URL=https://your-provider.com/v1
```

2. Test endpoint directly:

```bash
curl https://your-provider.com/v1/models \
  -H "Authorization: Bearer your-key"
```

3. Check provider compatibility (must be OpenAI-compatible)

4. Enable debug logging:

```bash
# View detailed logs
docker compose logs -f openwebui | grep -i "api"
```

### Models not appearing

**Solutions**:

1. Refresh model list in UI (gear icon → Refresh)

2. Check cache TTL in `.env`:

```bash
MODELS_CACHE_TTL=5  # Reduce to 5 seconds for testing
```

3. Restart OpenWebUI:

```bash
docker compose restart openwebui
```

4. Check provider logs:

```bash
docker compose logs openwebui | grep -i "model"
```

---

## Performance Issues

### Slow response times

**Solutions**:

1. Check resource usage:

```bash
docker stats
```

2. Increase memory limits:

```bash
# In .env
OPENWEBUI_MEMORY_LIMIT=8g
OPENWEBUI_CPU_LIMIT=4
```

3. Disable real-time save:

```bash
ENABLE_REALTIME_CHAT_SAVE=false
```

4. Increase timeouts:

```bash
AIOHTTP_CLIENT_TIMEOUT=600
```

5. Check network latency to providers

### High memory usage

**Solutions**:

1. Reduce embedding model size:

```bash
RAG_EMBEDDING_MODEL=sentence-transformers/paraphrase-MiniLM-L3-v2
```

2. Disable auto-update:

```bash
RAG_EMBEDDING_MODEL_AUTO_UPDATE=false
```

3. Clear cache:

```bash
rm -rf volumes/cache/*
docker compose restart openwebui
```

4. Set memory limits:

```bash
OPENWEBUI_MEMORY_LIMIT=4g
```

### RAG/Vector search slow

**Solutions**:

1. Reduce search results:

```bash
RAG_TOP_K=3
```

2. Optimize chunk size:

```bash
CHUNK_SIZE=500
CHUNK_OVERLAP=50
```

3. Consider switching to PGVector:

```bash
VECTOR_DB=pgvector
```

4. Disable hybrid search:

```bash
ENABLE_RAG_HYBRID_SEARCH=false
```

---

## Data & Storage

### Disk space issues

**Solutions**:

1. Check disk usage:

```bash
du -sh volumes/*
du -sh logs/*
```

2. Clean up logs:

```bash
# Truncate log files
truncate -s 0 logs/**/*.log

# Or adjust rotation in .env
LOG_MAX_SIZE=50m
LOG_MAX_FILE=3
```

3. Clean up old backups:

```bash
rm -f backups/owui-backup-*.tar.gz
```

4. Prune Docker system:

```bash
docker system prune -a
```

### Database corruption

**Symptoms**: SQLite errors, data inconsistencies

**Solutions**:

1. Restore from backup:

```bash
docker compose down
tar -xzf backups/owui-backup-YYYYMMDD-HHMMSS.tar.gz -C /tmp
cp /tmp/owui-backup-*/volumes/data/webui.db volumes/data/
docker compose up -d
```

2. Check database integrity:

```bash
sqlite3 volumes/data/webui.db "PRAGMA integrity_check;"
```

3. Rebuild database (last resort):

```bash
# Backup first!
./scripts/backup.sh

# Remove corrupted DB
rm volumes/data/webui.db

# Restart (creates new DB)
docker compose up -d
```

### Lost data after restart

**Solutions**:

1. Verify volume mounts in `docker-compose.yml`:

```yaml
volumes:
    - ./volumes/data:/app/backend/data:rw
```

2. Check permissions:

```bash
ls -la volumes/data
chmod 755 volumes/data
```

3. Ensure using bind mounts, not volumes:

```bash
docker volume ls  # Should not show owui volumes
```

---

## TLS/HTTPS Issues

### Certificate warnings in browser

**Expected behavior for self-signed certificates**

**Solutions**:

1. Trust the CA certificate (see README.md Security section)

2. For production, use Let's Encrypt:

```bash
# Update config/traefik.yml
# Change certResolver to "letsencrypt"
# Set your email
```

3. Or accept the warning and proceed (development only)

### Certificate expired

**Solutions**:

1. Regenerate certificates:

```bash
./scripts/generate-certs.sh --domain localhost --days 365 --force
```

2. Restart Traefik:

```bash
docker compose restart traefik
```

### Let's Encrypt challenge failing

**Symptoms**: ACME challenge errors in Traefik logs

**Solutions**:

1. Verify domain is publicly accessible:

```bash
curl http://your-domain.com/.well-known/acme-challenge/test
```

2. Check DNS configuration:

```bash
nslookup your-domain.com
```

3. Ensure ports 80/443 are open:

```bash
sudo ufw status
```

4. Use staging server for testing:

```yaml
# In config/traefik.yml
caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"
```

---

## Docker Issues

### Docker daemon errors

**Solutions**:

1. Restart Docker daemon:

```bash
# Linux
sudo systemctl restart docker

# macOS
# Restart Docker Desktop application
```

2. Check Docker status:

```bash
docker info
docker version
```

### Permission denied errors

**Solutions**:

1. Add user to docker group (Linux):

```bash
sudo usermod -aG docker $USER
newgrp docker
```

2. Check volume permissions:

```bash
sudo chown -R $USER:$USER volumes/
```

### Image pull failures

**Solutions**:

1. Check Docker Hub status: https://status.docker.com

2. Use mirror or retry:

```bash
docker compose pull
docker compose up -d
```

3. Check disk space:

```bash
df -h
docker system df
```

### Compose version issues

**Solutions**:

1. Update Docker Compose:

```bash
# Linux
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Or use Docker Compose v2 (docker compose)
```

2. Check version:

```bash
docker compose version
```

---

## Automatic Updates (Watchtower)

### Update failed / Container not starting after update

**Symptoms**: Container exits or fails to start after Watchtower update

**Solutions**:

1. Check Watchtower logs for errors:

```bash
docker compose logs --tail=100 watchtower
```

2. Watchtower should auto-rollback on failure. Verify:

```bash
# Check if container rolled back to previous image
docker compose ps
docker inspect owui-openwebui | grep Image
```

3. Manual rollback if needed:

```bash
# Stop services
docker compose down

# Pull specific version (replace with known-good version)
docker compose pull

# Or manually specify image version in docker-compose.yml
# image: ghcr.io/open-webui/open-webui:v0.1.234

# Restart
docker compose up -d
```

4. Check for breaking changes:

```bash
# View OpenWebUI release notes
# https://github.com/open-webui/open-webui/releases

# View Traefik release notes
# https://github.com/traefik/traefik/releases
```

### Disable automatic updates temporarily

```bash
# Stop Watchtower (updates will not run)
docker compose stop watchtower

# Re-enable later
docker compose start watchtower
```

### Disable automatic updates permanently

Edit `docker-compose.yml`:

1. Remove `watchtower` service
2. Remove `com.centurylinklabs.watchtower.enable=true` labels from services

Or stop and disable:

```bash
docker compose stop watchtower
docker compose rm watchtower
```

### Force immediate update check

```bash
# Run update check now (don't wait for schedule)
docker compose exec watchtower /watchtower --run-once
```

### Update notification not received

**If using email notifications:**

1. Verify SMTP configuration in `.env`:

```bash
cat .env | grep WATCHTOWER_NOTIFICATION
```

2. Check Watchtower logs for email errors:

```bash
docker compose logs watchtower | grep -i email
docker compose logs watchtower | grep -i notification
```

3. Test SMTP connectivity:

```bash
# From host machine
telnet smtp.example.com 587
```

### Watchtower using too many resources

**Solutions**:

1. Reduce memory/CPU limits in `.env`:

```bash
WATCHTOWER_MEMORY_LIMIT=128m
WATCHTOWER_CPU_LIMIT=0.1
```

2. Increase update interval (less frequent checks):

```bash
WATCHTOWER_SCHEDULE=0 0 4 * * 0  # Weekly instead of daily
WATCHTOWER_POLL_INTERVAL=604800  # 7 days
```

3. Restart Watchtower:

```bash
docker compose restart watchtower
```

### View update history

```bash
# Recent updates
docker compose logs --tail=200 watchtower | grep "Updated"

# All Watchtower activity
docker compose logs watchtower

# Export logs for analysis
docker compose logs watchtower > watchtower-history.log
```

---

## Advanced Diagnostics

### Enable debug logging

```bash
# Add to .env
LOG_LEVEL=DEBUG

# Restart
docker compose restart openwebui
```

### Container shell access

```bash
# OpenWebUI
docker compose exec openwebui bash

# Traefik
docker compose exec traefik sh
```

### Network debugging

```bash
# Test internal connectivity
docker compose exec openwebui ping traefik

# Check DNS resolution
docker compose exec openwebui nslookup traefik

# Check if OpenWebUI can reach internal port
docker compose exec traefik wget -O- http://openwebui:8080/health
```

### Complete reset

```bash
# WARNING: Deletes all data
docker compose down -v
rm -rf volumes/* logs/*
./scripts/setup.sh
docker compose up -d
```

---

## Getting Help

If these solutions don't resolve your issue:

1. **Check logs thoroughly**:

    ```bash
    docker compose logs --tail=200 > debug.log
    ```

2. **Run health check**:

    ```bash
    ./scripts/health-check.sh --verbose > health-check.log
    ```

3. **Collect system info**:

    ```bash
    docker version > system-info.txt
    docker compose version >> system-info.txt
    docker info >> system-info.txt
    ```

4. **OpenWebUI GitHub Issues**: https://github.com/open-webui/open-webui/issues

5. **Traefik Community**: https://community.traefik.io/

---

**Last Updated**: 2025
**Related**: [README.md](README.md) | [QUICKSTART.md](QUICKSTART.md)
