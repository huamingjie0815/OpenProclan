English | [中文](README.zh.md)

# Proclan app

Flutter client for Proclan. It reads your wall by day, opens an article (charts and video included), and deletes after confirmation.

From the repository root, `./scripts/run` starts the app and `./scripts/apk` builds the release APK. The server install is [../server/DEPLOY.md](../server/DEPLOY.md). Do not compile the app on the server.

`app/.env` holds `API_BASE` only. Copy `app/.env.example` and set that origin. `./scripts/run dev` reads `app/.env.development`. `./scripts/run production` reads `app/.env.production`. The same word works after `./scripts/apk`. A bare command still reads `app/.env`. Create those files on the machine. Do not commit them. Do not put a token in any of them, and do not hardcode the address in source.

Sign in with the username and password created on the server.

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`. Release uses the Android debug certificate so the person can install it themselves. Do not change the signing config.
