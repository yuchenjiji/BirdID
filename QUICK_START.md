# 🚀 快速开始指南

## 立即使用

### 📱 构建并发布新版本（推荐）

```bash
./build_all.sh
```

这一个命令会自动完成：
1. ✅ 构建 Android APK (release)
2. ✅ 上传到 Azure Blob Storage
3. ✅ 更新 Web 版本的下载链接
4. ✅ 重新构建 Web 版本

完成后，部署 `build/web/` 目录到你的 Web 服务器即可。

---

### 🌐 用户如何下载 APK

在 Web 版应用中：

1. 打开 **Settings（设置）**
2. 找到 **DOWNLOAD** 板块
3. 点击 **Download Android App**
4. 点击 **Download APK** 按钮
5. 下载开始！

---

### ⚙️ 首次配置

如果需要修改 Azure 配置，编辑这些文件：

**`build_and_upload.sh`**
```bash
AZURE_ACCOUNT="laow"        # 你的 Azure Storage 账户名
AZURE_CONTAINER="birdid-apk" # 你的容器名
```

**`update_apk_url.sh`** - 使用相同配置

---

### 📦 仅构建和上传 APK

```bash
./build_and_upload.sh
```

### 🔄 仅更新下载链接

```bash
./update_apk_url.sh
flutter build web --release
```

---

## 当前状态

- ✅ Web 版本已添加下载功能
- ✅ Azure Blob Storage 已配置
- ✅ 自动化脚本已就绪
- ✅ 最新 APK: `BirdID_1.0.0+1_20260211_172054.apk`

---

## 详细文档

- 📘 [完整使用指南](APK_DOWNLOAD_GUIDE.md)
- 📗 [实现说明](APK_DOWNLOAD_IMPLEMENTATION.md)

---

**需要帮助？** 查看上述文档或检查脚本输出信息。
