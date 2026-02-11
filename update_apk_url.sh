#!/bin/bash

# 此脚本用于上传新 APK 后更新 web 版本中的下载链接

# 配置
AZURE_ACCOUNT="laow"
AZURE_CONTAINER="birdid-apk"

echo "🔍 正在查找最新的 APK..."

# 获取 Azure Blob 中最新的 APK
LATEST_APK=$(az storage blob list \
  --account-name "$AZURE_ACCOUNT" \
  --container-name "$AZURE_CONTAINER" \
  --auth-mode key \
  --query "[?ends_with(name, '.apk')] | sort_by(@, &properties.lastModified) | [-1].name" \
  -o tsv 2>/dev/null)

if [ -z "$LATEST_APK" ]; then
    echo "❌ 未找到 APK 文件"
    echo "请手动指定: $0 <APK文件名>"
    exit 1
fi

DOWNLOAD_URL="https://${AZURE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER}/${LATEST_APK}"

echo "📝 最新 APK: $LATEST_APK"
echo "📝 下载链接: $DOWNLOAD_URL"

# 更新 main.dart 中的下载链接
sed -i "s|https://laow.blob.core.windows.net/birdid-apk/[^\"]*\.apk|$DOWNLOAD_URL|g" lib/main.dart

echo "✅ 下载链接已更新"
echo ""
echo "下一步："
echo "  1. flutter build web"
echo "  2. 部署 build/web 到你的服务器"

