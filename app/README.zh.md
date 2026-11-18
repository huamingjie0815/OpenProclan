[English](README.md) | 中文

# Proclan 应用

Proclan 的 Flutter 客户端。按天读自己的墙，打开文章（含图表和视频），确认后删除。

在仓库根目录用 `./scripts/run` 启动，用 `./scripts/apk` 打包。服务的安装在 [../server/DEPLOY.zh.md](../server/DEPLOY.zh.md)。不要在服务器上编译应用。

`app/.env` 只放 `API_BASE`。复制 `app/.env.example` 并写上这个源。`./scripts/run dev` 读取 `app/.env.development`。`./scripts/run production` 读取 `app/.env.production`。`./scripts/apk` 后面也可以加同样的词。不加词时仍读取 `app/.env`。这些文件留在本机，不要提交。不要写 token，也不要把地址写进源码。

用服务器上创建的用户名和密码登录。

APK 在 `app/build/app/outputs/flutter-apk/app-release.apk`。release 使用 Android debug 证书，供自己安装。不要改签名配置。
