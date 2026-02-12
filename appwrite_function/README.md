# Appwrite Cloud Function - Get Latest APK

## 功能
从 Azure Blob Storage 查询最新的 BirdID APK 下载链接

## 部署步骤

### 1. 创建 Appwrite 项目
1. 登录 [Appwrite Cloud](https://cloud.appwrite.io/)
2. 创建新项目 (例如: `BirdID`)
3. 记录 Project ID 和 API Endpoint

### 2. 创建 Cloud Function
在 Appwrite Console 中:
1. 进入 **Functions** → **Create Function**
2. 配置:
   - **Name**: `getLatestApk`
   - **Runtime**: `Node.js 18.0`
   - **Entrypoint**: `src/main.js`
   - **Execute Access**: `Any` (允许公开访问)

### 3. 设置环境变量
在 Function **Settings** → **Variables** 中添加:
- `AZURE_ACCOUNT`: `laow`
- `AZURE_CONTAINER`: `birdid-apk`
- `AZURE_SAS_TOKEN`: (可选，如果容器是私有的)

### 4. 部署代码
**方式 1: 通过 Appwrite Console (推荐)**
1. 将 `package.json` 和 `src/main.js` 打包成 `.tar.gz`
   ```bash
   cd appwrite_function
   tar -czf function.tar.gz package.json src/
   ```
2. 在 Appwrite Console 上传 `function.tar.gz`
3. 点击 **Deploy**

**方式 2: 使用 Appwrite CLI**
```bash
# 安装 Appwrite CLI
npm install -g appwrite-cli

# 登录
appwrite login

# 部署
appwrite functions createDeployment \
  --functionId=[YOUR_FUNCTION_ID] \
  --entrypoint="src/main.js" \
  --code="." \
  --activate=true
```

### 5. 获取 Function URL
部署成功后，在 Function 页面可以看到:
- **Function ID**: (例如: `65abc123def456`)
- **Endpoint**: `https://cloud.appwrite.io/v1/functions/[FUNCTION_ID]/executions`

### 6. 测试 Function
```bash
# 使用 curl 测试
curl -X POST \
  'https://cloud.appwrite.io/v1/functions/[FUNCTION_ID]/executions' \
  -H 'X-Appwrite-Project: [YOUR_PROJECT_ID]' \
  -H 'Content-Type: application/json'
```

或者在 Appwrite Console 的 Function 页面点击 **Execute** 测试。

### 7. 配置 CORS (重要!)
在 Appwrite Project Settings → **Platforms** 中:
1. 添加 **Web Platform**
2. **Hostname**: 你的 Web 应用域名 (例如: `oldweng-birdid.hf.space`)
3. 或使用 `*` (允许所有来源，仅用于测试)

## API 响应示例

**成功响应:**
```json
{
  "success": true,
  "data": {
    "fileName": "BirdID_1.0.0+1_20260212_012811.apk",
    "downloadUrl": "https://laow.blob.core.windows.net/birdid-apk/BirdID_1.0.0+1_20260212_012811.apk",
    "size": 45678901,
    "lastModified": "2026-02-12T01:28:11Z"
  }
}
```

**失败响应:**
```json
{
  "success": false,
  "error": "No APK files found in storage"
}
```

## Flutter 集成

在 Flutter 中调用此 Function，请参考 `lib/main.dart` 中的 `_getLatestApkUrl()` 方法。

需要在 `pubspec.yaml` 中添加:
```yaml
dependencies:
  http: ^1.2.0  # 用于 HTTP 请求
```

或者使用 Appwrite Flutter SDK (可选):
```yaml
dependencies:
  appwrite: ^11.0.0
```

## 注意事项

1. **容器访问权限**: 确保 Azure Blob Storage 容器设置为 **公开访问** 或提供有效的 SAS Token
2. **CORS**: 必须在 Appwrite 中配置允许的域名
3. **Function 限额**: Appwrite 免费计划有执行次数限制，注意监控使用量
4. **缓存**: 建议在 Flutter 中缓存 APK 链接（例如 5 分钟），避免频繁调用
