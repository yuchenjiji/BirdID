#!/bin/bash
set -e

# ============================================
# 🌐 BirdID Web Deployment Script
# ============================================
# Deploys Flutter web build to nginx server
# ============================================

# Configuration
VM_IP="134.33.96.248"
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/birdid_deploy_key"
REMOTE_DIR="/var/www/dont_click_me"
LOCAL_BUILD_DIR="build/web"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "           🌐 Deploying Web to nginx"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if build exists
if [[ ! -d "$LOCAL_BUILD_DIR" ]]; then
    echo "❌ Error: build/web/ directory not found!"
    echo "   Please run 'flutter build web' first."
    exit 1
fi

# Check if SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    echo "❌ Error: SSH key not found at $SSH_KEY"
    exit 1
fi

echo "📦 Preparing deployment..."
echo "   Source: $LOCAL_BUILD_DIR"
echo "   Target: $VM_USER@$VM_IP:$REMOTE_DIR"
echo ""

# Backup existing deployment (on remote server)
echo "💾 Creating backup on server..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" \
    "sudo cp -r $REMOTE_DIR ${REMOTE_DIR}_backup_\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true"

# Deploy using rsync (efficient, only transfers changed files)
echo "🚀 Deploying files..."
rsync -avz --delete \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    "$LOCAL_BUILD_DIR/" \
    "$VM_USER@$VM_IP:/tmp/birdid_web_deploy/"

# Move files with sudo (because /var/www/dont_click_me may need sudo)
echo "📁 Moving files to web directory..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" << 'ENDSSH'
    sudo rm -rf /var/www/dont_click_me/*
    sudo cp -r /tmp/birdid_web_deploy/* /var/www/dont_click_me/
    sudo chown -R nginx:nginx /var/www/dont_click_me
    sudo chmod -R 755 /var/www/dont_click_me
    rm -rf /tmp/birdid_web_deploy
ENDSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "           ✅ Deployment Successful!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🌍 Your site should be live at:"
echo "   http://$VM_IP"
echo ""
echo "💡 Backup saved on server: ${REMOTE_DIR}_backup_*"
echo ""
