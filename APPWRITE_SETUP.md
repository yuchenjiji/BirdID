# Appwrite 配置指南

## 快速开始

### 1. 部署 Appwrite Function

1. **登录 Appwrite Cloud**
   - 访问: https://cloud.appwrite.io/
   - 使用教育邮箱登录获取更多权益

2. **创建项目**
   - 点击 "Create Project"
   - 项目名称: `BirdID` (或任意名称)
   - 记录 **Project ID**

3. **创建 Cloud Function**
   - 进入 Functions → Create Function
   - 配置:
     * Name: `getLatestApk`
     * Runtime: `Node.js 18.0`
     * Entrypoint: `src/main.js`
     * Execute Access: `Any` (重要！允许公开调用)

4. **上传代码**
   ```bash
   cd appwrite_function
   tar -czf function.tar.gz package.json src/
   ```
   - 在 Appwrite Console 上传 `function.tar.gz`
   - 点击 **Deploy**

5. **设置环境变量**
   在 Function Settings → Variables 添加:
   ```
   AZURE_ACCOUNT = laow
   AZURE_CONTAINER = birdid-apk
   ```

6. **获取 Function ID**
   - 部署成功后，在 Function 页面复制 **Function ID**
   - 格式类似: `65abc123def456789`

### 2. 配置 Flutter 应用

编辑 `lib/main.dart` 第 176-177 行:

```dart
static const String projectId = "YOUR_PROJECT_ID"; // 替换为第2步的 Project ID
static const String functionId = "YOUR_FUNCTION_ID"; // 替换为第6步的 Function ID
```

### 3. 配置 CORS (重要!)

在 Appwrite Project Settings → **Platforms**:

1. 添加 **Web Platform**
2. **Name**: `BirdID Web`
3. **Hostname**: 你的 Web 应用域名
   - 开发环境: `localhost`
   - 生产环境: `oldweng-birdid.hf.space` (或你的域名)

### 4. 测试 Function

在 Appwrite Console 的 Function 页面:
1. 点击 **Execute** 按钮
2. 查看执行结果
3. 应该返回类似:
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

### 5. 测试 Flutter 集成

1. 更新配置后重新运行应用:
   ```bash
   flutter run -d chrome
   ```

2. 进入 Settings → Download Android App
3. 点击 "Download APK" 按钮
4. 应该会自动获取最新 APK 链接并开始下载

## 故障排查

### 问题: Function 执行失败
- 检查环境变量是否正确设置
- 确认 Azure Blob Storage 容器为公开访问
- 查看 Function 执行日志

### 问题: CORS 错误
- 确保在 Platforms 中添加了 Web 应用域名
- 检查 Function Execute Access 设置为 `Any`

### 问题: 超时
- Appwrite Function 默认超时 15 秒
- 如果需要更长时间，在 Function Settings 中调整

## 优势

✅ **动态更新**: 每次上传新 APK 后，Web 应用自动获取最新链接
✅ **零修改**: 不需要修改代码或重新部署 Web 应用
✅ **教育权益**: 利用 Appwrite 教育计划的免费额度
✅ **备用方案**: 如果 Appwrite 调用失败，自动使用备用链接
✅ **缓存优化**: 5 分钟缓存，减少 API 调用次数

## 进阶: 添加版本信息显示

可以扩展 Function 返回更多信息:
- 版本号
- 文件大小
- 更新日期
- 更新说明

然后在 Flutter 的下载对话框中显示这些信息。
