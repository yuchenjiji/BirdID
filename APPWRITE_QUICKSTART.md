# 快速参考：Appwrite 配置

## 🎯 你需要做的事情

### Step 1: 在 Appwrite Console 完成这些
1. 访问 https://cloud.appwrite.io/
2. 创建项目，获得: `Project ID`
3. 创建 Function，获得: `Function ID`
4. 上传 `appwrite_function/function.tar.gz`
5. 设置环境变量:
   - `AZURE_ACCOUNT` = `laow`
   - `AZURE_CONTAINER` = `birdid-apk`
6. 在 Platforms 添加域名: `oldweng-birdid.hf.space`

### Step 2: 修改一行代码
编辑 `lib/main.dart` 第 176-177 行:

```dart
// 原来 (TODO 需要替换):
static const String projectId = "YOUR_PROJECT_ID";
static const String functionId = "YOUR_FUNCTION_ID";

// 改成你的 (例如):
static const String projectId = "65abc123def456";
static const String functionId = "789ghi012jkl345";
```

### Step 3: 测试
```bash
flutter run -d chrome
```

进入 Settings → Download Android App，点击下载按钮。

---

## 📦 如何打包 Function

```bash
cd appwrite_function
tar -czf function.tar.gz package.json src/
```

然后在 Appwrite Console 上传 `function.tar.gz`

---

## ✅ 完成后的效果

- ✅ 每次上传新 APK 到 Azure，Web 应用自动获取最新链接
- ✅ 不需要修改代码或重新部署 Web
- ✅ 5 分钟缓存，性能优秀
- ✅ 失败时自动降级到备用链接

---

详细文档:
- 部署指南: `APPWRITE_SETUP.md`
- 实施总结: `DYNAMIC_APK_IMPLEMENTATION.md`
