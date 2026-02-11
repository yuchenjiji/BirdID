# 📖 脚本使用指南

## 🚀 最简单的方式（推荐）

### 一键构建和发布所有版本

```bash
./build_all.sh
```

**这个命令会自动完成：**
1. ✅ 构建 Android APK (release 版本)
2. ✅ 上传 APK 到 Azure Blob Storage  
3. ✅ 更新 Web 版本中的下载链接
4. ✅ 重新构建 Web 版本

**完成后：**
- Android APK 已上传到 Azure
- Web 版本在 `build/web/` 目录
- 只需要部署 `build/web/` 到你的 Web 服务器

---

## 📱 分步使用（如果需要单独操作）

### 1️⃣ 只构建和上传 Android APK

```bash
./build_and_upload.sh
```

**输出示例：**
```
🚀 开始构建 APK...
✓ Built build/app/outputs/flutter-apk/app-release.apk (56.6MB)
✅ APK 构建成功
📤 上传 APK 到 Azure Blob Storage...
✅ 上传成功！
文件名: BirdID_1.0.0+1_20260211_172054.apk
URL: https://laow.blob.core.windows.net/birdid-apk/BirdID_1.0.0+1_20260211_172054.apk
```

### 2️⃣ 更新 Web 版本的下载链接

```bash
./update_apk_url.sh
```

**作用：**
- 自动找到 Azure 上最新的 APK
- 更新 `lib/main.dart` 中的下载 URL

**输出示例：**
```
🔍 正在查找最新的 APK...
📝 最新 APK: BirdID_1.0.0+1_20260211_172054.apk
📝 下载链接: https://laow.blob.core.windows.net/birdid-apk/BirdID_1.0.0+1_20260211_172054.apk
✅ 下载链接已更新
```

### 3️⃣ 构建 Web 版本

```bash
flutter build web --release
```

---

## 🔒 提交前的安全检查

在 `git commit` 之前运行：

```bash
./git-safety-check.sh
```

**检查内容：**
- ✅ 确保没有密钥文件被暂存
- ✅ 确保没有 APK 文件被暂存
- ✅ 确保脚本中没有硬编码密钥

**输出示例：**
```
🔍 正在检查 Git 状态...
📋 检查暂存文件（即将提交）...
✅ 未发现硬编码密钥
✅ 没有敏感文件被跟踪
==================================
✅ 安全检查通过！可以安全提交。
```

---

## 📋 完整的发布流程示例

### 场景：发布新版本的应用

```bash
# Step 1: 一键构建所有版本
./build_all.sh

# Step 2: 检查 Web 构建结果
ls build/web/

# Step 3: 提交代码前的安全检查
./git-safety-check.sh

# Step 4: 提交代码
git add .
git commit -m "release: v1.0.1"
git push

# Step 5: 部署 Web 版本到服务器
# (根据你的部署方式，例如：)
# scp -r build/web/* user@server:/var/www/birdid/
# 或使用其他部署工具
```

---

## ⚙️ 脚本配置说明

### 如果需要修改 Azure 配置

编辑以下文件，修改这两个变量：

**`build_and_upload.sh`**
```bash
AZURE_ACCOUNT="laow"          # 改成你的 Azure Storage 账户名
AZURE_CONTAINER="birdid-apk"  # 改成你的容器名
```

**`update_apk_url.sh`**
```bash
AZURE_ACCOUNT="laow"          # 改成你的 Azure Storage 账户名
AZURE_CONTAINER="birdid-apk"  # 改成你的容器名
```

---

## ❓ 常见问题

### Q: 脚本无法执行？
```bash
# 确保脚本有执行权限
chmod +x build_all.sh
chmod +x build_and_upload.sh
chmod +x update_apk_url.sh
chmod +x git-safety-check.sh
```

### Q: 上传失败？
确保：
1. 已运行 `az login` 登录 Azure
2. Azure 账户名和容器名配置正确
3. 有 Azure Storage 的访问权限

### Q: 如何查看最新上传的 APK？
```bash
az storage blob list \
  --account-name laow \
  --container-name birdid-apk \
  --auth-mode key \
  --output table
```

### Q: 只想更新 Web 版本？
```bash
flutter build web --release
# 然后部署 build/web/ 目录
```

---

## 📊 脚本速查表

| 脚本 | 用途 | 耗时 |
|------|------|------|
| `./build_all.sh` | 一键构建所有 | ~3-5 分钟 |
| `./build_and_upload.sh` | 构建+上传 APK | ~2-3 分钟 |
| `./update_apk_url.sh` | 更新下载链接 | <5 秒 |
| `./git-safety-check.sh` | 安全检查 | <5 秒 |

---

## 🎯 推荐工作流

### 日常开发
```bash
# 只需要构建和测试
flutter run
```

### 准备发布
```bash
# 一键完成所有构建
./build_all.sh
```

### 提交代码
```bash
# 安全检查
./git-safety-check.sh

# 提交
git add .
git commit -m "your message"
git push
```

---

**需要更多帮助？** 查看详细文档：
- 📘 [APK_DOWNLOAD_GUIDE.md](APK_DOWNLOAD_GUIDE.md) - 功能详细说明
- 📗 [GIT_SAFETY_SUMMARY.md](GIT_SAFETY_SUMMARY.md) - Git 安全配置
- 📙 [QUICK_START.md](QUICK_START.md) - 快速开始
