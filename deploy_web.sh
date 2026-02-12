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
REMOTE_DIR="/var/www/laow_app"
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

# Deploy using rsync (efficient, only transfers changed files)
echo "🚀 Deploying files..."
rsync -avz --delete \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    "$LOCAL_BUILD_DIR/" \
    "$VM_USER@$VM_IP:/tmp/birdid_web_deploy/"

# Move files with sudo (because /var/www/laow_app may need sudo)
echo "📁 Moving files to web directory..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" << 'ENDSSH'
    sudo rm -rf /var/www/laow_app/*
    sudo cp -r /tmp/birdid_web_deploy/* /var/www/laow_app/
    sudo chown -R nginx:nginx /var/www/laow_app
    sudo chmod -R 755 /var/www/laow_app
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
