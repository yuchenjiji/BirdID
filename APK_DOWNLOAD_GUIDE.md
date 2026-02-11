# APK 下载功能使用指南

## 功能说明

Web 版 Bird ID 现在包含一个 Android APK 下载板块，用户可以在 Web 应用中下载最新的 Android 原生应用。

## 如何使用

### 对于用户

1. 在 Web 版应用中，打开 **Settings（设置）**
2. 找到 **DOWNLOAD** 板块
3. 点击 **Download Android App**
4. 在弹出的对话框中，点击 **Download APK**
5. 复制下载链接并在浏览器中打开，或直接点击复制按钮

### 对于开发者

#### 一键构建和部署

使用集成脚本一次性完成所有步骤：

```bash
./build_all.sh
```

这个脚本会自动：
1. 构建 Android APK (release)
2. 上传 APK 到 Azure Blob Storage
3. 更新 Web 版本中的下载链接
4. 重新构建 Web 版本

#### 手动步骤

**1. 构建并上传 APK**
```bash
./build_and_upload.sh
```

**2. 更新 Web 版本的下载链接**
```bash
./update_apk_url.sh
```

**3. 重新构建 Web 版本**
```bash
flutter build web --release
```

**4. 部署 Web 版本**
将 `build/web/` 目录的内容部署到你的 Web 服务器。

## 配置说明

### Azure Blob Storage 配置

在以下文件中修改 Azure 配置：

- `build_and_upload.sh`
- `update_apk_url.sh`
- `android/upload_to_azure.sh`

```bash
AZURE_ACCOUNT="your-account-name"
AZURE_CONTAINER="your-container-name"
```

### 下载链接配置

下载链接位于 `lib/main.dart` 中的 `_downloadApk` 函数：

```dart
const String downloadUrl = 
    "https://your-account.blob.core.windows.net/your-container/YourApp.apk";
```

运行 `./update_apk_url.sh` 会自动更新此链接为最新的 APK。

## 文件结构

```
/workspaces/BirdID/
├── build_and_upload.sh       # 构建 APK 并上传到 Azure
├── update_apk_url.sh          # 更新 Web 版本中的下载链接
├── build_all.sh               # 一键构建所有版本
├── android/
│   └── upload_to_azure.sh     # Azure 上传辅助脚本
└── lib/
    └── main.dart              # 包含下载功能的主文件
```

## 功能特点

- ✅ 自动生成带版本号和时间戳的 APK 文件名
- ✅ 上传到 Azure Blob Storage
- ✅ 生成 24 小时有效的 SAS 下载链接
- ✅ Web 版本中集成下载功能（仅在 Web 平台显示）
- ✅ 用户可以直接复制下载链接

## 注意事项

1. 确保已安装并登录 Azure CLI (`az login`)
2. 确保有 Azure Storage Account 的访问权限
3. APK 文件会以版本号和时间戳命名，便于管理
4. 每次上传新 APK 后，记得运行 `./update_apk_url.sh` 更新 Web 版本

## 未来改进

- [ ] 添加 `url_launcher` 包，支持直接在新标签页打开下载链接
- [ ] 显示 APK 文件大小和上传日期
- [ ] 支持显示多个历史版本
- [ ] 添加二维码下载功能
