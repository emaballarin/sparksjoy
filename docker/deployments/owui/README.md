# OpenWebUI Production Deployment

Production-ready Docker deployment of OpenWebUI with Traefik reverse proxy, HTTPS-only access, comprehensive security hardening, and full-featured configuration.

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Deployment Modes](#deployment-modes)
- [Security](#security)
- [Monitoring](#monitoring)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## ✨ Features

### Core Capabilities

- **OpenWebUI**: Modern web interface for LLM interactions
- **Multi-Provider Support**: Ollama, OpenAI, Anthropic, and custom endpoints
- **RAG (Retrieval-Augmented Generation)**: ChromaDB vector database with document upload
- **Code Execution**: Built-in Python interpreter (Pyodide/Jupyter)
- **HTTPS-Only Access**: Traefik reverse proxy with TLS termination
- **Docker Network Isolation**: Reserved subnet for future service expansion

### Security Features

- Self-signed TLS certificates (with Let's Encrypt support)
- HTTPS-only access (no HTTP port exposed)
- Security headers (HSTS, CSP, X-Frame-Options, etc.)
- Rate limiting middleware
- No direct port exposure
- JWT authentication with configurable expiration
- Cookie security flags
- `no-new-privileges` container security

### Operational Features

- Automated setup script
- Health check validation
- Backup/restore utilities
- Log rotation
- Resource limits
- GPU support (CUDA)
- Comprehensive documentation

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet/User                         │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ HTTPS :8443 (HTTPS-ONLY)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│  Traefik Reverse Proxy                                       │
│  • TLS termination (self-signed or Let's Encrypt)            │
│  • HTTPS-only access (no HTTP)                               │
│  • Security headers middleware                               │
│  • Rate limiting                                             │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ Docker Network: owui-network (172.29.0.0/16)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│  OpenWebUI :8080 (internal)                                  │
│  • Web interface                                             │
│  • Authentication & user management                          │
│  • Multi-provider LLM support                                │
│  • RAG with ChromaDB                                         │
│  • Code execution (Pyodide)                                  │
│  • Data: ./volumes/data                                      │
│  • Cache: ./volumes/cache                                    │
│  • Vector DB: ./volumes/chroma                               │
└───────────────────────────────────────────────────────────┬─┘
                                                              │
                                                              │
┌─────────────────────────────────────────────────────────────▼┐
│  External Services (via host.docker.internal)                │
│  • Ollama: :11434 (optional)                                 │
│  • OpenAI API: https://api.openai.com/v1                     │
│  • Other providers: Anthropic, Google, etc.                  │
└──────────────────────────────────────────────────────────────┘
```

### Network Architecture

- **Custom bridge network**: `owui-network` (subnet: `172.29.0.0/16`)
- **Internal communication**: Services communicate via Docker DNS
- **External access**: Only through Traefik on port 8443 (HTTPS-only)
- **Expandable**: Reserved subnet allows adding future services to the same network

## 📦 Requirements

### Software

- **Docker**: 20.10+ with Docker Compose v2
- **Operating System**: Linux, macOS, or Windows (with WSL2)
- **OpenSSL**: For certificate generation

### Hardware (Minimum)

- **CPU**: 2 cores
- **RAM**: 4 GB
- **Storage**: 10 GB

### Hardware (Recommended)

- **CPU**: 4+ cores
- **RAM**: 8+ GB
- **Storage**: 50+ GB SSD
- **GPU** (optional): NVIDIA GPU with CUDA support for accelerated inference

### Ports

- **8443**: HTTPS (main application access, HTTPS-only)

## 🚀 Quick Start

### 1. Initial Setup

```bash
# Clone or navigate to project directory
cd /path/to/owui

# Run automated setup (choose one):

# Option 1: Standard setup with self-signed certificates
./scripts/setup.sh --domain your-domain.com

# Option 2: Tailscale setup (recommended if using Tailscale)
./scripts/setup.sh --use-tailscale --domain your-device.ts.net

# This will:
# - Create .env from template
# - Generate WEBUI_SECRET_KEY
# - Create directory structure
# - Generate TLS certificates (Tailscale or self-signed)
```

### 2. Configure Environment

Edit `.env` and set required values:

```bash
# REQUIRED: Generate strong secret key
WEBUI_SECRET_KEY=$(openssl rand -base64 32)

# Set your domain
DOMAIN=your-domain.com
WEBUI_URL=https://your-domain.com:8443

# Configure external providers
OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...

# Configure Ollama endpoint (if using external Ollama)
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

### 3. Start Services

```bash
# Start all services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 4. Access OpenWebUI

1. Open browser: `https://your-domain.com:8443`
2. Accept self-signed certificate warning
3. Create admin account (first login)
4. Configure model providers in Settings

### 5. Verify Health

```bash
# Run health check
./scripts/health-check.sh --verbose
```

## ⚙️ Configuration

### Environment Variables

See `.env.example` for complete configuration options. Key variables:

#### Core Settings

```bash
PROJECT_NAME=owui                # Container naming
DOMAIN=localhost                 # Your domain
WEBUI_SECRET_KEY=...            # JWT signing key (REQUIRED)
```

#### Authentication

```bash
ENABLE_SIGNUP=false             # Allow new user registration
DEFAULT_USER_ROLE=user          # Role for new users (user/admin/pending)
JWT_EXPIRES_IN=7d               # Token expiration
```

#### External Providers

```bash
# Ollama
ENABLE_OLLAMA_API=true
OLLAMA_BASE_URL=http://host.docker.internal:11434

# OpenAI
ENABLE_OPENAI_API=true
OPENAI_API_KEY=sk-...
OPENAI_API_BASE_URL=https://api.openai.com/v1

# Multiple endpoints (semicolon-separated)
# OPENAI_API_KEYS=sk-key1;sk-key2
# OLLAMA_BASE_URLS=http://ollama1:11434;http://ollama2:11434
```

#### RAG Configuration

```bash
VECTOR_DB=chroma                # Vector database (chroma/pgvector/qdrant/milvus)
RAG_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
RAG_TOP_K=5                     # Number of search results
CHUNK_SIZE=1000                 # Document chunk size
ENABLE_RAG_HYBRID_SEARCH=false  # BM25 + vector search
```

#### Resource Limits

```bash
OPENWEBUI_MEMORY_LIMIT=4g
OPENWEBUI_CPU_LIMIT=2
TRAEFIK_MEMORY_LIMIT=512m
```

#### GPU Support

```bash
# Uncomment deploy.resources.reservations section in docker-compose.yml
GPU_DEVICE_IDS=0                # GPU device IDs (comma-separated)
OPENWEBUI_VERSION=cuda          # Use CUDA-enabled image
```

### Traefik Configuration

#### Static Configuration (`config/traefik.yml`)

- HTTPS-only entry point
- Certificate resolvers
- Providers (Docker, file)
- Application logging

#### Dynamic Configuration (`config/traefik-dynamic.yml`)

- TLS options and cipher suites
- Security headers middleware
- Rate limiting rules
- Compression settings

## 🚢 Deployment Modes

### Production Mode (with Traefik)

```bash
# Use main docker-compose.yml
docker compose up -d

# Access via HTTPS
https://your-domain.com:8443
```

**Features:**

- HTTPS-only with TLS termination
- Security headers
- Rate limiting
- No HTTP port exposed

### GPU-Accelerated Mode

1. Uncomment GPU section in `docker-compose.yml`:

```yaml
deploy:
    resources:
        reservations:
            devices:
                - driver: nvidia
                  device_ids: ["0"]
                  capabilities: [gpu]
```

2. Use CUDA image:

```bash
OPENWEBUI_VERSION=cuda docker compose up -d
```

## 🔒 Security

### Security Checklist

- [ ] **Run configuration validation**: `./scripts/validate-config.sh --strict`
- [ ] Generate strong `WEBUI_SECRET_KEY` (32+ characters, validated automatically)
- [ ] Enable backup encryption with GPG
- [ ] Disable `ENABLE_SIGNUP` in production
- [ ] Set `DEFAULT_USER_ROLE=pending` for approval workflow
- [ ] Use Let's Encrypt for public deployments
- [ ] Configure `CORS_ALLOW_ORIGIN` with specific domain
- [ ] Enable secure cookie flags on HTTPS
- [ ] Review and restrict `BYPASS_ADMIN_ACCESS_CONTROL`
- [ ] Set appropriate `RAG_FILE_MAX_SIZE` and `RAG_FILE_MAX_COUNT`
- [ ] Regularly update Docker images (automatic via Watchtower)
- [ ] Implement encrypted backup strategy
- [ ] Monitor logs for suspicious activity

### Configuration Validation

**Validate your configuration before deployment:**

```bash
# Run validation script
./scripts/validate-config.sh

# Strict mode (fail on warnings)
./scripts/validate-config.sh --strict

# Check specific .env file
./scripts/validate-config.sh --env /path/to/.env
```

**What gets validated:**

- WEBUI_SECRET_KEY strength (minimum 32 characters)
- JWT token expiration format
- Network configuration (CIDR validation)
- URL consistency (WEBUI_URL vs CORS_ALLOW_ORIGIN)
- Port configuration validity
- Backup encryption settings
- Let's Encrypt email format
- Security settings (auth, cookies)

### TLS/HTTPS Setup

#### Self-Signed Certificates (Default)

```bash
# Generate certificates
./scripts/generate-certs.sh --domain your-domain.com --days 365

# Certificates created in certs/
# - server.crt (certificate)
# - server.key (private key)
# - ca.crt (CA certificate for browser trust)
```

**Trust self-signed certificate:**

- **Chrome/Edge**: Settings → Privacy → Manage certificates → Authorities → Import `ca.crt`
- **Firefox**: Preferences → Privacy → Certificates → View Certificates → Authorities → Import
- **macOS**: Open Keychain Access → Import `ca.crt` → Trust "Always"
- **Linux**: Copy to `/usr/local/share/ca-certificates/` → `sudo update-ca-certificates`

#### Tailscale Certificates (Recommended for Tailscale Networks)

**Best option if you're using Tailscale!** These certificates are automatically trusted by all devices in your Tailscale network.

**Requirements:**

- Tailscale installed and running
- Domain accessible via Tailscale (MagicDNS name or `.ts.net` domain)

**Setup:**

```bash
# During initial setup
./scripts/setup.sh --use-tailscale --domain your-device.ts.net

# Or generate certificates manually
./scripts/generate-certs.sh --use-tailscale --domain your-device.ts.net

# Certificates created in certs/
# - server.crt (Tailscale certificate)
# - server.key (private key)
```

**Benefits:**

- ✅ No browser security warnings for Tailscale clients
- ✅ No manual CA certificate installation required
- ✅ Automatic certificate rotation by Tailscale
- ✅ Valid, non-self-signed certificates
- ✅ Works with any Tailscale MagicDNS name

**Note:** Devices accessing via Tailscale will trust certificates automatically. Non-Tailscale clients will still see warnings.

#### Let's Encrypt (Production)

1. Update `config/traefik.yml`:

```yaml
certificatesResolvers:
    letsencrypt:
        acme:
            email: "your-email@example.com"
            storage: "/acme/acme.json"
            httpChallenge:
                entryPoint: web
```

2. Update Docker labels in `docker-compose.yml`:

```yaml
- "traefik.http.routers.owui-https.tls.certresolver=letsencrypt"
```

3. Ensure port 443 is publicly accessible for TLS-ALPN challenge

### Security Headers

Configured in `config/traefik-dynamic.yml`:

- **HSTS**: `max-age=31536000; includeSubDomains; preload`
- **X-Frame-Options**: `DENY`
- **X-Content-Type-Options**: `nosniff`
- **CSP**: Restricts content sources
- **Permissions-Policy**: Disables unnecessary features

### Rate Limiting

- **General**: 100 req/s average, 50 burst
- **API**: 20 req/s (stricter for API endpoints)
- **Auth**: 5 req/min (very strict for login)

## 📊 Monitoring

### Service Status

```bash
# Check container status
docker compose ps

# View resource usage
docker stats

# Check logs
docker compose logs -f openwebui
docker compose logs -f traefik
```

### Health Checks

```bash
# Automated health check (container-level only)
./scripts/health-check.sh --verbose

# Manual container health check
docker compose ps
docker inspect --format='{{.State.Health.Status}}' owui-openwebui
```

**Health Check Configuration:**
All health checks are configurable via `.env`:

```bash
HEALTHCHECK_INTERVAL=30s          # How often to check
HEALTHCHECK_TIMEOUT=10s           # Maximum time for check
HEALTHCHECK_RETRIES=3             # Failures before unhealthy
HEALTHCHECK_START_PERIOD_TRAEFIK=10s
HEALTHCHECK_START_PERIOD_OPENWEBUI=60s
```

**Note**: External endpoint checks disabled for security. Internal Docker health checks monitor container status.

### Log Files

```
logs/
├── openwebui/        # Application logs
└── traefik/
    └── traefik.log   # Traefik application logs
```

**Docker Container Logs:**
Managed automatically by Docker logging driver (configured in `.env`):

- Max size: 100MB per file
- Max files: 5 (rotation)
- View with: `docker compose logs -f`

**Application Logs (volume-mounted):**
Require manual log rotation setup:

```bash
# Install logrotate configuration (optional but recommended)
sudo ./scripts/setup-logrotate.sh

# Configuration includes:
# - Daily rotation
# - Keep 7 days
# - Compression enabled
# - Automatic cleanup
```

**Manual log rotation:**

```bash
# View current log sizes
du -sh logs/*

# Manually rotate logs
sudo logrotate -f /etc/logrotate.d/openwebui

# Or truncate manually
truncate -s 0 logs/openwebui/*.log
truncate -s 0 logs/traefik/*.log
```

## 💾 Backup & Restore

### Create Backup

```bash
# Full backup (data + config + certs)
./scripts/backup.sh

# Custom output directory
./scripts/backup.sh --output /path/to/backups

# Different compression
./scripts/backup.sh --compress xz

# 🔒 Encrypted backup (RECOMMENDED for production)
./scripts/backup.sh --encrypt --gpg-recipient your-email@example.com
```

**⚠️ Security Note:**
Backups contain sensitive data including API keys, secrets, and certificates. **Always use encryption for production backups.**

**Backup includes:**

- OpenWebUI data (`volumes/data`)
- Cache (`volumes/cache`)
- Vector database (`volumes/chroma` - isolated volume)
- Configuration (`.env`, `config/`)
- TLS certificates (`certs/`)
- Docker Compose files

**Integrity Verification:**
All backups automatically include SHA256 checksums for integrity verification:

```bash
# Verify a backup
./scripts/verify-backup.sh backups/owui-backup-YYYYMMDD-HHMMSS.tar.gz

# Checksum is shown in backup output
# Checksum file: backup.tar.gz.sha256
```

### Restore Backup

**Automated restore (recommended):**

```bash
# Restore with automatic verification and decryption
./scripts/restore.sh backups/owui-backup-YYYYMMDD-HHMMSS.tar.gz

# Restore encrypted backup (auto-detects .gpg extension)
./scripts/restore.sh backup.tar.gz.gpg

# Skip integrity verification (not recommended)
./scripts/restore.sh backup.tar.gz --skip-verify
```

The restore script automatically:

- Verifies backup integrity using SHA256 checksums
- Decrypts GPG-encrypted backups
- Stops services before restore
- Creates a safety backup of current data
- Restarts services after restore

**Manual restore (for encrypted backups):**

```bash
# 1. Verify integrity
./scripts/verify-backup.sh backup.tar.gz.gpg

# 2. Decrypt backup
gpg --decrypt --output backup.tar.gz backup.tar.gz.gpg

# 3. Stop services
docker compose down

# 4. Extract backup
tar -xzf backup.tar.gz -C /tmp

# 5. Restore files
cp -r /tmp/owui-backup-YYYYMMDD-HHMMSS/* .

# 6. Start services
docker compose up -d
```

**Manual restore (for unencrypted backups):**

```bash
# 1. Verify integrity
./scripts/verify-backup.sh backup.tar.gz

# 2. Stop services
docker compose down

# 3. Extract backup
tar -xzf backups/owui-backup-YYYYMMDD-HHMMSS.tar.gz -C /tmp

# 4. Restore files
cp -r /tmp/owui-backup-YYYYMMDD-HHMMSS/* .

# 5. Start services
docker compose up -d
```

### Backup Encryption Setup

**Generate GPG key (one-time setup):**

```bash
# Generate a new GPG key
gpg --full-generate-key

# List your keys to find the email
gpg --list-keys

# Configure in .env
BACKUP_ENABLE_ENCRYPTION=true
BACKUP_GPG_RECIPIENT=your-email@example.com
```

**To backup the GPG key itself (store securely!):**

```bash
# Export private key (keep this VERY secure!)
gpg --export-secret-keys --armor your-email@example.com > gpg-private-key.asc

# Export public key
gpg --export --armor your-email@example.com > gpg-public-key.asc
```

**To restore GPG key on another system:**

```bash
# Import private key
gpg --import gpg-private-key.asc

# Trust the key
gpg --edit-key your-email@example.com
# Type: trust, then 5 (ultimate), then quit
```

### Backup Strategy

**Recommended:**

- **Frequency**: Daily automated backups (cron)
- **Retention**: Keep 7 daily, 4 weekly, 12 monthly backups
- **Storage**: Off-site backup location (S3, NAS, etc.)
- **Testing**: Verify restore procedure quarterly

**Example cron jobs:**

```cron
# Daily encrypted backup at 2 AM (RECOMMENDED)
0 2 * * * cd /path/to/owui && ./scripts/backup.sh --encrypt --output /mnt/backup

# Or without encryption (not recommended for production)
0 2 * * * cd /path/to/owui && ./scripts/backup.sh --output /mnt/backup
```

## 🔧 Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions.

### Common Issues

#### Service won't start

```bash
# Check logs
docker compose logs openwebui

# Verify .env exists and contains WEBUI_SECRET_KEY
cat .env | grep WEBUI_SECRET_KEY

# Reset and restart
docker compose down
docker compose up -d
```

#### HTTPS certificate errors

```bash
# Regenerate certificates
./scripts/generate-certs.sh --domain your-domain.com --force

# Import ca.crt to browser (see Security section)
```

#### Can't connect to Ollama

```bash
# Verify Ollama is running on host
curl http://localhost:11434/api/tags

# Check OpenWebUI logs for connection errors
docker compose logs openwebui | grep ollama

# Verify host.docker.internal mapping
docker compose exec openwebui ping -c 3 host.docker.internal
```

#### Out of memory errors

```bash
# Increase memory limits in .env
OPENWEBUI_MEMORY_LIMIT=8g

# Restart services
docker compose up -d
```

## 🔬 Advanced Topics

### Automatic Updates with Watchtower

OpenWebUI includes automatic container updates via Watchtower for OpenWebUI, Traefik, and Watchtower itself.

**Configuration:**

- **Update Schedule**: Daily at 4 AM UTC (configurable via `WATCHTOWER_SCHEDULE`)
- **Monitored Containers**: OpenWebUI, Traefik, Watchtower (label-based opt-in)
- **Rollback**: Automatic on update failure
- **Image Cleanup**: Old images removed (keeps 1 previous image for rollback)
- **Rolling Restart**: Updates one container at a time for zero-downtime

**View Update Logs:**

```bash
# Real-time logs
docker compose logs -f watchtower

# Recent updates
docker compose logs --tail=100 watchtower
```

**Disable Auto-Updates:**

```bash
# Temporarily stop Watchtower
docker compose stop watchtower

# Permanently remove (edit docker-compose.yml)
# Remove watchtower service and labels
```

**Force Immediate Update Check:**

```bash
# Run update check now instead of waiting for schedule
docker compose exec watchtower /watchtower --run-once
```

**Manual Update (Alternative):**

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d
```

**Configure Update Schedule:**

Edit `.env` to change schedule (cron format):

```bash
# Daily at 4 AM (default)
WATCHTOWER_SCHEDULE=0 0 4 * * *

# Every 6 hours
WATCHTOWER_SCHEDULE=0 0 */6 * * *

# Weekly on Sunday at 3 AM
WATCHTOWER_SCHEDULE=0 0 3 * * 0
```

**Email Notifications (Optional):**

Uncomment and configure in `.env`:

```bash
WATCHTOWER_NOTIFICATIONS=email
WATCHTOWER_NOTIFICATION_EMAIL_FROM=watchtower@example.com
WATCHTOWER_NOTIFICATION_EMAIL_TO=admin@example.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.example.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=username
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=password
```

**Security Notes:**

- Docker socket mounted read-only
- Only containers with `watchtower.enable=true` label are updated
- Automatic rollback on failure maintains service availability
- Updates happen during low-traffic hours (4 AM UTC by default)

### Add Additional Services

The Docker network is designed for expansion:

1. Create new service in separate `docker-compose.yml`
2. Connect to existing network:

```yaml
networks:
    owui-network:
        external: true
        name: owui-network
```

3. Configure Traefik routing via labels

### PostgreSQL Backend

Switch from SQLite to PostgreSQL:

```bash
# Add to docker-compose.yml
postgres:
  image: postgres:15
  environment:
    POSTGRES_DB: openwebui
    POSTGRES_USER: openwebui
    POSTGRES_PASSWORD: <strong-password>
  volumes:
    - ./volumes/postgres:/var/lib/postgresql/data
  networks:
    - owui-network

# Update .env
DATABASE_URL=postgresql://openwebui:<password>@postgres:5432/openwebui
```

### PGVector for RAG

Use PostgreSQL with pgvector extension:

```bash
# In .env
VECTOR_DB=pgvector
PGVECTOR_DB_URL=postgresql://user:pass@postgres:5432/openwebui
PGVECTOR_INITIALIZE_MAX_VECTOR_LENGTH=1536
```

### External Content Extraction

Add Apache Tika for advanced document processing:

```bash
# Add service
tika:
  image: apache/tika:latest
  networks:
    - owui-network

# Configure in .env
CONTENT_EXTRACTION_ENGINE=tika
TIKA_SERVER_URL=http://tika:9998
```

### Monitoring Stack

Add Prometheus + Grafana:

```yaml
# See ../vllmowui/docker-compose.monitoring.yml for reference
prometheus:
    image: prom/prometheus:latest
    # ... configuration

grafana:
    image: grafana/grafana:latest
    # ... configuration
```

## 📚 Documentation

- **QUICKSTART.md**: 5-minute setup guide
- **TROUBLESHOOTING.md**: Common issues and solutions
- **OpenWebUI Docs**: https://docs.openwebui.com/
- **Traefik Docs**: https://doc.traefik.io/traefik/

## 📄 License

This deployment configuration follows the license terms of the respective projects:

- **OpenWebUI**: MIT License
- **Traefik**: MIT License

## 🤝 Contributing

Improvements welcome! Please:

1. Test changes thoroughly
2. Update documentation
3. Follow existing patterns
4. Submit detailed pull requests

## 📞 Support

- **Issues**: See TROUBLESHOOTING.md
- **OpenWebUI**: https://github.com/open-webui/open-webui
- **Traefik**: https://community.traefik.io/

---

**Created**: 2025
**Maintained**: Active
**Status**: Production-Ready
