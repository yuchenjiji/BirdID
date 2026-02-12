/**
 * Appwrite Cloud Function - Get Latest APK
 * 
 * 从 Azure Blob Storage 查询最新的 BirdID APK 下载链接
 * 
 * 环境变量:
 * - AZURE_ACCOUNT: Azure Storage 账户名 (例如: laow)
 * - AZURE_CONTAINER: Blob 容器名 (例如: birdid-apk)
 * - AZURE_SAS_TOKEN: (可选) SAS token，如果容器不是公开访问
 */

import { BlobServiceClient } from '@azure/storage-blob';

export default async ({ req, res, log, error }) => {
  try {
    // 获取环境变量
    const AZURE_ACCOUNT = process.env.AZURE_ACCOUNT || 'laow';
    const AZURE_CONTAINER = process.env.AZURE_CONTAINER || 'birdid-apk';
    const AZURE_SAS_TOKEN = process.env.AZURE_SAS_TOKEN || '';

    log(`Querying Azure Blob Storage: ${AZURE_ACCOUNT}/${AZURE_CONTAINER}`);

    // 构建 Azure Blob Service URL
    const accountUrl = `https://${AZURE_ACCOUNT}.blob.core.windows.net`;
    let blobServiceClient;

    if (AZURE_SAS_TOKEN) {
      // 使用 SAS Token (用于私有容器)
      const sasUrl = `${accountUrl}?${AZURE_SAS_TOKEN}`;
      blobServiceClient = new BlobServiceClient(sasUrl);
    } else {
      // 公开访问（无需认证）
      blobServiceClient = new BlobServiceClient(accountUrl);
    }

    const containerClient = blobServiceClient.getContainerClient(AZURE_CONTAINER);

    // 列出所有 .apk 文件
    const apkBlobs = [];
    for await (const blob of containerClient.listBlobsFlat()) {
      if (blob.name.endsWith('.apk')) {
        apkBlobs.push({
          name: blob.name,
          lastModified: blob.properties.lastModified,
          size: blob.properties.contentLength,
        });
      }
    }

    if (apkBlobs.length === 0) {
      log('No APK files found');
      return res.json({
        success: false,
        error: 'No APK files found in storage',
      }, 404);
    }

    // 按最后修改时间排序，获取最新的
    apkBlobs.sort((a, b) => b.lastModified - a.lastModified);
    const latestApk = apkBlobs[0];

    log(`Latest APK found: ${latestApk.name}`);

    // 构建下载URL
    const downloadUrl = `${accountUrl}/${AZURE_CONTAINER}/${latestApk.name}`;

    // 返回结果
    return res.json({
      success: true,
      data: {
        fileName: latestApk.name,
        downloadUrl: downloadUrl,
        size: latestApk.size,
        lastModified: latestApk.lastModified.toISOString(),
      },
    });

  } catch (err) {
    error(`Error fetching latest APK: ${err.message}`);
    return res.json({
      success: false,
      error: err.message,
    }, 500);
  }
};
