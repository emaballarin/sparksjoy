# OpenWebUI Quick Start Guide

Get OpenWebUI running with HTTPS in 5 minutes.

## Prerequisites

- Docker and Docker Compose installed
- 4 GB RAM minimum
- Port 8443 available (HTTPS-only)

## Installation Steps

### 1. Run Setup Script

```bash
cd /path/to/owui
./scripts/setup.sh --domain localhost
```

This automatically:

- Creates `.env` with generated secrets
- Generates self-signed TLS certificates
- Creates required directories
- Sets proper permissions

### 2. Start Services

```bash
docker compose up -d
```

### 3. Access OpenWebUI

Open browser: **https://localhost:8443**

**Note**: You'll see a security warning (expected for self-signed certificates). Click "Advanced" → "Proceed to localhost".

### 4. Create Admin Account

On first visit:

1. Fill in registration form
2. First user becomes admin automatically
3. Log in with your credentials

### 5. Configure Providers

#### Option A: Use Ollama (Local)

1. Install Ollama on your host: https://ollama.com/download
2. Pull a model:
    ```bash
    ollama pull llama3.2
    ```
3. OpenWebUI will auto-detect Ollama models
4. Start chatting!

#### Option B: Use OpenAI

1. Get API key from: https://platform.openai.com/api-keys
2. In OpenWebUI:
    - Click Settings → Connections
    - Select "OpenAI"
    - Enter API key
    - Save
3. Models will appear in chat interface

#### Option C: Use Anthropic Claude

1. Get API key from: https://console.anthropic.com/
2. Add to `.env`:
    ```bash
    ENABLE_OPENAI_API=true
    OPENAI_API_BASE_URL=https://api.anthropic.com/v1
    OPENAI_API_KEY=sk-ant-your-key-here
    ```
3. Restart: `docker compose restart openwebui`

## Verification

```bash
# Check services are healthy
./scripts/health-check.sh

# View logs
docker compose logs -f openwebui
```

## What's Next?

- **Upload Documents**: Use RAG for document Q&A (Settings → Documents)
- **Enable Code Execution**: Already enabled! Try asking for Python code
- **Customize**: Edit `.env` for advanced configuration
- **Backup**: Run `./scripts/backup.sh` to create first backup

## Troubleshooting

### Can't access OpenWebUI

```bash
# Check if containers are running
docker compose ps

# Check logs for errors
docker compose logs openwebui
```

### Ollama not detected

```bash
# Verify Ollama is running
curl http://localhost:11434/api/tags

# Check connection from container
docker compose exec openwebui curl http://host.docker.internal:11434/api/tags
```

### Certificate warnings

This is normal for self-signed certificates. See README.md Security section for instructions on trusting the certificate.

## Complete Documentation

For detailed configuration, security hardening, and advanced features, see [README.md](README.md).

---

**Time to completion**: ~5 minutes
**Next steps**: [README.md](README.md) | [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
