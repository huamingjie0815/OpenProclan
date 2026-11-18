English | [中文](README.zh.md)

# Proclan app

Flutter client for Proclan. It reads your wall by day, opens an article (charts and video included), and deletes after confirmation.

From the repository root, `./scripts/run` starts the app and `./scripts/apk` builds the release APK. The server install is [../server/DEPLOY.md](../server/DEPLOY.md). Do not compile the app on the server.

Every push to `main` builds the production APK in GitHub Actions with `API_BASE=https://proclan.online`; download it from the run's artifacts (30 days). Point the build elsewhere with the repository variable `PROCLAN_API_BASE`.

`app/.env` holds `API_BASE` only. Copy `app/.env.example` and set that origin. `./scripts/run dev` reads `app/.env.development`. `./scripts/run production` reads `app/.env.production`. The same word works after `./scripts/apk`. A bare command still reads `app/.env`. Create those files on the machine. Do not commit them. Do not put a token in any of them, and do not hardcode the address in source.

Sign in with the username and password created on the server.

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`. Release signs with a fixed release key: put `storeFile`, `storePassword`, `keyAlias`, `keyPassword`, and `storeType` in `app/android/key.properties`, which stays out of git. Without that file a release build falls back to the debug certificate, and such a build cannot replace an installed one. GitHub Actions writes the file from the repository secrets `PROCLAN_KEYSTORE_BASE64`, `PROCLAN_KEYSTORE_PASSWORD`, `PROCLAN_KEY_ALIAS`, and `PROCLAN_KEY_PASSWORD`.
