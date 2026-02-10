# BirdID Web 部署指南

## 📦 构建成功

Web 应用已成功编译！输出位于 `build/web` 目录。

## 🔧 适配修改说明

### 1. **平台检测**
- 使用 `kIsWeb` 标志区分 Web 和移动平台
- 添加条件导入处理 `dart:io` 在 Web 上的不可用问题

### 2. **设备 ID 生成**
- **移动端**: 使用 `DeviceInfoPlugin` 获取硬件唯一 ID
- **Web 端**: 使用时间戳生成唯一 ID (`web_${timestamp}`)

### 3. **文件上传**
- **移动端**: 使用文件路径 (`MultipartFile.fromFile`)
- **Web 端**: 使用文件字节数据 (`MultipartFile.fromBytes`)
- 添加 `withData: kIsWeb` 参数确保 Web 端读取文件内容

### 4. **录音功能**
- **移动端**: 完整支持录音功能
- **Web 端**: 
  - 隐藏录音菜单选项
  - 仅显示文件上传功能
  - Web 端录音需要 HTTPS 和额外的浏览器权限处理

### 5. **API 服务**
- 添加 `identifyBirdWeb()` 方法处理字节数据
- 提取 `_parseResults()` 共享解析逻辑
- 移动端和 Web 端使用相同的后端接口

## 🚀 部署方式

### 方式 1: 本地测试
```bash
cd build/web
python3 -m http.server 8080
# 访问 http://localhost:8080
```

### 方式 2: GitHub Pages
1. 将 `build/web` 内容推送到 `gh-pages` 分支
2. 在仓库设置中启用 GitHub Pages
3. 访问 `https://username.github.io/BirdID`

### 方式 3: Vercel / Netlify
1. 连接 GitHub 仓库
2. 设置构建命令: `flutter build web --release`
3. 发布目录: `build/web`
4. 自动部署

### 方式 4: Firebase Hosting
```bash
firebase init hosting
# 选择 build/web 作为发布目录
firebase deploy
```

### 方式 5: 自托管服务器 (Nginx)
```nginx
server {
    listen 80;
    server_name your-domain.com;
    root /var/www/birdid/build/web;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

## ⚠️ 注意事项

### CORS 问题
后端 API (`https://oldweng-birdnet.hf.space`) 需要允许跨域请求。如果遇到 CORS 错误：
1. 确认后端配置了 CORS 头
2. 或使用代理服务器

### 浏览器兼容性
- **推荐**: Chrome, Edge, Firefox 最新版本
- **需要**: 支持 ES6+ 和 WebAssembly
- **文件选择器**: 所有现代浏览器都支持

### 功能限制
| 功能 | 移动端 | Web 端 |
|-----|-------|--------|
| 文件上传识别 | ✅ | ✅ |
| 录音识别 | ✅ | ❌ |
| 历史记录 | ✅ | ✅ |
| 云端同步 | ✅ | ✅ |
| 设备唯一 ID | ✅ (硬件ID) | ✅ (时间戳) |

### 性能优化建议
1. **启用 HTTPS**: 必需，某些浏览器功能要求安全上下文
2. **CDN 加速**: 使用 CDN 分发静态资源
3. **Gzip 压缩**: 服务器端启用压缩减少传输大小
4. **Service Worker**: Flutter 自动生成，支持离线缓存

## 🔍 测试清单

- [ ] 文件上传功能正常
- [ ] API 请求成功返回结果
- [ ] 历史记录正确显示和保存
- [ ] 主题切换正常工作
- [ ] 云端同步功能正常
- [ ] 响应式布局在不同屏幕尺寸下正常
- [ ] 浏览器控制台无错误信息

## 📱 PWA 支持

应用已配置为 PWA (Progressive Web App)：
- **manifest.json**: 定义应用元数据
- **Service Worker**: 自动生成，支持离线访问
- **图标**: 使用 `web/icons/` 中的图标

用户可以在浏览器中"添加到主屏幕"，像原生应用一样使用。

## 🛠️ 重新构建

如需修改代码后重新构建：

```bash
flutter clean
flutter pub get
flutter build web --release
```

添加性能分析：
```bash
flutter build web --release --profile
```

生成 Wasm 版本（实验性，更好的性能）：
```bash
flutter build web --release --wasm
```

## 📞 故障排查

### 问题 1: 白屏或加载失败
- 检查浏览器控制台错误
- 确认 `index.html` 正确加载
- 验证服务器 MIME 类型配置正确

### 问题 2: API 调用失败
- 检查网络请求（开发者工具 Network 标签）
- 确认后端 URL 正确且可访问
- 检查 CORS 配置

### 问题 3: 文件上传失败
- 确认文件大小在服务器限制内
- 检查文件格式是否支持
- 验证网络稳定性

---

✅ **Web 应用已就绪，可以部署！**
