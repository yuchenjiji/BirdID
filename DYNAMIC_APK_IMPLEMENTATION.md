# APK 下载链接动态管理方案 - 实施总结

## 📋 方案概述

之前的问题：APK 下载链接硬编码在 `main.dart` 中，每次更新 APK 都需要修改代码并重新部署 Web 应用。

**新方案：使用 Appwrite Cloud Function 动态获取最新 APK 链接**

## 🏗️ 架构设计

```
┌─────────────────┐
│  Flutter Web    │
│   Application   │
└────────┬────────┘
         │ 1. 用户点击下载
         ▼
┌─────────────────┐
│ AppwriteService │ (lib/main.dart)
│  getLatestApk() │
└────────┬────────┘
         │ 2. HTTP Request
         ▼
┌─────────────────┐
│  Appwrite Cloud │
│     Function    │ (Node.js)
└────────┬────────┘
         │ 3. Query Blobs
         ▼
┌─────────────────┐
│  Azure Blob     │
│    Storage      │ (laow/birdid-apk)
└─────────────────┘
         │ 4. 返回最新 APK URL
         ▼
┌─────────────────┐
│  User Browser   │ (开始下载)
└─────────────────┘
```

## 📁 新增文件

### 1. Appwrite Cloud Function
```
appwrite_function/
├── package.json          # Node.js 依赖配置
├── src/
│   └── main.js          # Function 主逻辑
└── README.md            # 部署文档
```

**功能**: 查询 Azure Blob Storage，返回最新 .apk 文件的下载链接

### 2. Flutter 服务层
**位置**: `lib/main.dart` (第 172-261 行)

**新增类**: `AppwriteService`
- `getLatestApkUrl()`: 调用 Appwrite Function
- `getLatestApkUrlCached()`: 带 5 分钟缓存的版本

### 3. 配置文档
- `APPWRITE_SETUP.md`: 完整的部署和配置指南
- `.gitignore`: 添加 Appwrite 相关忽略规则

## 🔧 实现细节

### Flutter 代码修改

**修改的方法**:
1. `_downloadApk()` (第 1343 行)
   - 从 Appwrite 获取最新链接
   - 显示加载状态
   - 失败时有备用链接

**新增依赖**:
```yaml
dependencies:
  http: ^1.6.0  # 用于 HTTP 请求
```

### Appwrite Function 逻辑

**输入**: 
- 环境变量: `AZURE_ACCOUNT`, `AZURE_CONTAINER`

**处理**:
1. 连接到 Azure Blob Storage
2. 列出所有 `.apk` 文件
3. 按修改时间排序
4. 返回最新文件信息

**输出**:
```json
{
  "success": true,
  "data": {
    "fileName": "BirdID_1.0.0+1_20260212_012811.apk",
    "downloadUrl": "https://laow.blob.core.windows.net/...",
    "size": 45678901,
    "lastModified": "2026-02-12T01:28:11Z"
  }
}
```

## ✅ 优势

1. **零代码修改部署** 🚀
   - 上传新 APK 后，Web 应用自动获取最新链接
   - 不需要重新构建或部署 Web 应用

2. **利用教育权益** 🎓
   - Appwrite 教育计划免费额度充足
   - 无需额外成本

3. **性能优化** ⚡
   - 5 分钟缓存机制
   - 减少不必要的 API 调用

4. **容错机制** 🛡️
   - Appwrite 失败时使用备用链接
   - 超时保护（10 秒）

5. **可扩展性** 📈
   - 可轻松添加版本信息、更新日志等
   - 支持多平台（Android、iOS、Windows）

## 📝 待完成任务

### 必须完成（应用才能正常工作）:

- [ ] **1. 创建 Appwrite 项目**
  - 访问 https://cloud.appwrite.io/
  - 创建项目并记录 `Project ID`

- [ ] **2. 部署 Cloud Function**
  - 上传 `appwrite_function` 代码
  - 设置环境变量
  - 记录 `Function ID`

- [ ] **3. 配置 CORS**
  - 在 Appwrite Platforms 添加 Web 应用域名
  - 开发: `localhost`
  - 生产: `oldweng-birdid.hf.space`

- [ ] **4. 更新 Flutter 配置**
  - 编辑 `lib/main.dart` 第 176-177 行
  - 填入 `projectId` 和 `functionId`

- [ ] **5. 测试**
  - 在 Appwrite Console 测试 Function
  - 在 Flutter Web 测试下载功能

### 可选优化:

- [ ] 在下载对话框显示 APK 版本和大小
- [ ] 添加下载进度显示
- [ ] 支持多版本 APK（stable/beta）
- [ ] 发送下载统计到后端

## 🚀 快速开始

1. **阅读配置指南**:
   ```bash
   cat APPWRITE_SETUP.md
   ```

2. **部署 Appwrite Function**:
   ```bash
   cd appwrite_function
   tar -czf function.tar.gz package.json src/
   # 然后在 Appwrite Console 上传
   ```

3. **更新 Flutter 配置**:
   编辑 `lib/main.dart` 填入你的 Appwrite 配置

4. **测试**:
   ```bash
   flutter run -d chrome
   ```

## 📚 参考文档

- [Appwrite Cloud Functions](https://appwrite.io/docs/products/functions)
- [Azure Blob Storage Node.js SDK](https://learn.microsoft.com/azure/storage/blobs/storage-quickstart-blobs-nodejs)
- [Flutter HTTP Package](https://pub.dev/packages/http)

## 🆘 需要帮助?

如果遇到问题，请检查：
1. `APPWRITE_SETUP.md` 的故障排查部分
2. Appwrite Console 的 Function 执行日志
3. Flutter 应用的 Debug Console 输出

---

**实施时间**: 2026-02-12  
**方案选择**: Appwrite Cloud Function 动态查询 Azure (最灵活)  
**状态**: ✅ 代码实现完成，等待配置部署
