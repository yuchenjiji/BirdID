#!/bin/bash

# 配置信息
AZURE_ACCOUNT="your-storage-account-name"
AZURE_CONTAINER="apk-builds"
# 可选：使用 SAS token 或 connection string
# AZURE_SAS_TOKEN="your-sas-token"
# AZURE_CONNECTION_STRING="your-connection-string"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 开始构建 APK...${NC}"

# 构建 APK（可以改为 --release 用于生产环境）
flutter build apk --release

# 检查构建是否成功
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ APK 构建失败${NC}"
    exit 1
fi

echo -e "${GREEN}✅ APK 构建成功${NC}"

# APK 文件路径
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

# 生成带时间戳的文件名
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
VERSION=$(grep "version:" pubspec.yaml | sed 's/version: //' | tr -d ' ')
BLOB_NAME="BirdID_${VERSION}_${TIMESTAMP}.apk"

echo -e "${GREEN}📤 上传 APK 到 Azure Blob Storage...${NC}"

# 方式 1: 使用 Azure CLI (需要先 az login)
az storage blob upload \
  --account-name "$AZURE_ACCOUNT" \
  --container-name "$AZURE_CONTAINER" \
  --name "$BLOB_NAME" \
  --file "$APK_PATH" \
  --auth-mode login \
  --overwrite

# 方式 2: 使用 Connection String (取消注释以使用)
# az storage blob upload \
#   --container-name "$AZURE_CONTAINER" \
#   --file "$APK_PATH" \
#   --name "$BLOB_NAME" \
#   --connection-string "$AZURE_CONNECTION_STRING" \
#   --overwrite

# 方式 3: 使用 AzCopy (性能更好，取消注释以使用)
# azcopy copy "$APK_PATH" "https://${AZURE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER}/${BLOB_NAME}?${AZURE_SAS_TOKEN}"

# 检查上传是否成功
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 上传成功！${NC}"
    echo -e "文件名: ${BLOB_NAME}"
    echo -e "URL: https://${AZURE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER}/${BLOB_NAME}"
    
    # 可选：生成下载链接（需要容器为公开或使用 SAS）
    echo -e "\n${GREEN}生成 SAS 下载链接（24小时有效）...${NC}"
    EXPIRY=$(date -u -d "+24 hours" '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -v+24H '+%Y-%m-%dT%H:%MZ')
    az storage blob generate-sas \
      --account-name "$AZURE_ACCOUNT" \
      --container-name "$AZURE_CONTAINER" \
      --name "$BLOB_NAME" \
      --permissions r \
      --expiry "$EXPIRY" \
      --https-only \
      --auth-mode login \
      --full-uri
else
    echo -e "${RED}❌ 上传失败${NC}"
    exit 1
fi
