#!/bin/bash

# 完整的构建和部署流程
# 1. 构建 Android APK
# 2. 上传到 Azure
# 3. 更新 Web 版本的下载链接
# 4. 重新构建 Web 版本

set -e  # 遇到错误立即退出

echo "🚀 开始完整的构建和部署流程..."
echo ""

# Step 1: 构建并上传 APK
echo "📱 Step 1/3: 构建并上传 Android APK"
./build_and_upload.sh

echo ""
echo "🔄 Step 2/3: 更新 Web 版本的下载链接"
./update_apk_url.sh

echo ""
echo "🌐 Step 3/3: 重新构建 Web 版本"
flutter build web --release

echo ""
echo "✅ 所有步骤完成！"
echo ""
echo "📦 生成的文件："
echo "  - Android APK: build/app/outputs/flutter-apk/app-release.apk (已上传到 Azure)"
echo "  - Web 应用: build/web/"
echo ""
echo "🚀 下一步: 部署 build/web/ 到你的 Web 服务器"
