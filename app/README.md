English | [中文](README.zh.md)

# Proclan app

Flutter client for the announcement wall. It reads cards, filters by category, opens an article, and deletes after confirmation.

From the repository root, `./scripts/run` starts the app and `./scripts/apk` builds the release APK. The server install is [../server/DEPLOY.md](../server/DEPLOY.md). Do not compile the app on the server.

`app/.env` holds `API_BASE` only. Copy `app/.env.example` and set that origin. Do not put a token in the file, and do not hardcode the address in source.

Sign in with the username and password created on the server.

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`. Release uses the Android debug certificate so the person can install it themselves. Do not change the signing config.
