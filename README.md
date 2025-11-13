# banb — Bash Ansible‑like Toolkit

## 📖 What is banb?

`banb` stands for Bash Ansible‑like. It’s a collection of Bash functions (`banb_*`) that simulate the behavior of Ansible modules. The goal is to bring declarative, idempotent, and human‑friendly automation into plain Bash scripts without needing Python or the full Ansible runtime.

Each function:

- Mimics the arguments of its Ansible counterpart (--name, --state, --enabled, etc.).
- Provides --help documentation inline.
- Supports --dry-run mode for safe testing.
- Optionally supports --become for privilege escalation.

Modules currently implemented include:

- banb_copy: manage files and inline content safely.
- banb_service: manage systemd services.
- banb_sysctl: manage kernel parameters via sysctl.
- banb_package: install/remove packages via your package manager.

## 📦 Getting banb from GitHub

Clone the repository into your local library path:

```
git clone https://github.com/bottlelee/banb.git ~/.local/lib/banb
```

Source the loader script to bring all functions into your shell:

```
source ~/.local/lib/banb/loader.sh
```

Now you can call any `banb_*` function directly in your scripts.

## 🧪 Example Script

Here’s a Bash script that demonstrates how multiple `banb` functions work together:

```
#!/bin/bash
set -euo pipefail

# Load banb modules
source ~/.local/lib/banb/load_banb_modules.sh

# Ensure nginx package is present
banb_package --name=nginx --state=present --update_cache=true --become

# Copy custom nginx config
banb_copy \
  --src=/home/user/nginx.conf \
  --dest=/etc/nginx/nginx.conf \
  --owner=root --group=root --mode=0644 \
  --backup=true --become

# Apply sysctl tuning for web workloads
banb_sysctl \
  --sysctl-dict="net.core.somaxconn=65535 net.ipv4.ip_forward=1" \
  --dest=/etc/sysctl.d/99-web.conf \
  --backup=true --reload=true --become

# Restart nginx service to apply changes
banb_service --name=nginx --state=restarted --enabled=true --become
```

Run it with:

```
bash setup_web.sh
```

This script will:

- Install nginx if missing.
- Copy a custom config file with backup and permissions.
- Apply kernel tuning safely via a temp file and reload sysctl.
- Restart and enable the nginx service.
