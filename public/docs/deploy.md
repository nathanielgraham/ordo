# Ordo Deployment Preparation & Hetzner Migration Guide

**Last Updated:** June 13, 2026  
**Goal:** Prepare everything locally now so the move to Hetzner is smooth.

---

## Phase 1: Current Machine Preparation (Do This Now)

### 1.1 Document Current System State

```
dpkg --get-selections > packages.txt
cat /etc/postfix/main.cf > postfix-main.cf
printenv | grep -E 'EMAIL|SMTP|DB|ORDO' > env.txt
```

### 1.2 Create Deployment Script (deploy.sh)

Create file `deploy.sh` in your project root:

```
#!/bin/bash
set -e

echo "🚀 Starting Ordo deployment..."

git pull origin main

cpanm --installdeps .

sudo systemctl restart ordo-app.service
sudo systemctl restart ordo-minion.service

echo "✅ Deployment completed successfully at $(date)"
```

Make executable:
```
chmod +x deploy.sh
```

### 1.3 Daily Database Backup Script

Create `backup-db.sh`:

```
#!/bin/bash
BACKUP_DIR="/var/backups/ordo"
DATE=$(date +%Y-%m-%d_%H-%M)

mkdir -p $BACKUP_DIR

cp /home/nathaniel/ordo/ordo.db $BACKUP_DIR/ordo_$DATE.db 2>/dev/null || echo "No database found"

gzip $BACKUP_DIR/ordo_$DATE.db 2>/dev/null

find $BACKUP_DIR -type f -mtime +14 -delete

echo "Database backup completed: $BACKUP_DIR/ordo_$DATE.db.gz"
```

Make executable and add to cron:
```
chmod +x backup-db.sh
crontab -e
```

Add this line:
```
0 3 * * * /home/nathaniel/ordo/backup-db.sh >> /var/log/ordo-backup.log 2>&1
```

---

## Phase 2: Hetzner VPS Setup (When Ready to Move)

### 2.1 Create VPS on Hetzner
- Image: **Debian 12**
- Type: **CX22** (2 vCPU, 4 GB RAM) or **CPX21**
- Enable **Backups**
- Add your SSH key

### 2.2 Initial Server Setup

```
sudo apt update && sudo apt upgrade -y
sudo apt install curl git ufw fail2ban htop postfix mailutils -y
```

**Postfix Install:**
- Choose **"Internet Site"**
- System mail name: press Enter (use `localhost`)

### 2.3 Firewall

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw --force enable
```

### 2.4 Postfix Configuration

```
sudo nano /etc/postfix/main.cf
```

Set these lines:
```
myhostname = localhost
myorigin = /etc/mailname
mydestination = $myhostname, localhost.localdomain, localhost
inet_interfaces = loopback-only
inet_protocols = all
```

Restart:
```
sudo systemctl restart postfix
```

Test:
```
echo "Test from Hetzner" | mail -s "Ordo Hetzner Test" nathanielgraham1@gmail.com
```

---
