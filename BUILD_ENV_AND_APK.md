# 构建环境与 APK 产物记录

本文档记录本项目的**实测可复现构建过程**：从零搭建安卓构建环境并成功产出 APK。

---

## 一、构建环境（已验证）

| 组件 | 版本 / 路径 | 说明 |
|------|------------|------|
| Flutter | 3.0.0（Dart 2.17） | 单代码库原生编译 |
| Android SDK | `compileSdk 33`、`targetSdk 33`、`minSdk 21` | platform 31/33、build-tools 33.0.1、NDK 21.1.6352462、platform-tools |
| **JDK** | **17**（Zulu 17.0.2） | ⚠️ Gradle 7.4 不支持 JDK 18/20，必须用 17 |
| Gradle | 7.4（Wrapper，阿里云镜像） | `distributionUrl` 已改为国内镜像 |
| 操作系统 | Ubuntu 22.04 / 类 Linux | — |

> 关键修复点：
> 1. **JDK 版本**：JDK 20 会导致 `Unsupported class file major version 64`，必须降到 **17**。
> 2. **compileSdk**：视频播放器底层 ExoPlayer 2.18.5 要求 `compileSdk ≥ 33`，已将 `android/app/build.gradle` 的 `compileSdkVersion` 由默认的 31 提升为 **33**。
> 3. **Gradle 镜像**：`services.gradle.org` 在本环境下载超时，已改用阿里云镜像下载 Gradle 发行包。

---

## 二、构建命令

```bash
cd local_media_app

# 环境变量（按需替换为你本机的路径）
export ANDROID_HOME=/opt/android-sdk
export JAVA_HOME=/opt/jdk17
export PATH=$JAVA_HOME/bin:$PATH:$ANDROID_HOME/platform-tools

# 安装 Flutter 依赖
flutter pub get

# 生成按 ABI 拆分的发布版 APK（体积最小，推荐分发）
flutter build apk --release --split-per-abi
```

---

## 三、APK 产物

构建成功后位于 `build/app/outputs/flutter-apk/`：

| 文件 | 体积 | 适用设备 |
|------|------|----------|
| `app-arm64-v8a-release.apk` | ≈ 7.5 MB | **主流 64 位手机（推荐首选）** |
| `app-armeabi-v7a-release.apk` | ≈ 7.1 MB | 老旧 32 位设备 |
| `app-x86_64-release.apk` | ≈ 7.6 MB | 模拟器 / x86 设备 |
| `app.apk` | ≈ 7.1 MB | 通用包（未拆分 ABI） |

> 已分发到工作区：`/workspace/apk/*.apk`。
> 单 ABI 包仅约 **7.5 MB**，满足"安装包体积小"的强约束。

---

## 四、安装到手机验证

```bash
# 连接安卓真机（开启 USB 调试）后：
adb install -r /workspace/apk/app-arm64-v8a-release.apk
```

或在手机文件管理器中直接打开该 APK 安装。

---

## 五、常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `Unsupported class file major version 64` | JDK 版本过高 | 换用 **JDK 17** |
| `exoplayer ... requires compileSdkVersion to be set to 33` | compileSdk 太低 | `build.gradle` 中 `compileSdkVersion 33` |
| Gradle 下载 `services.gradle.org` 超时 | 网络受限 | 改用阿里云镜像（见 `gradle-wrapper.properties`） |
| `Could not compile initialization script` | `~/.gradle/init.gradle` 语法错误 | 检查/移除该损坏脚本 |

---

详见 `README.md`（功能、打包、iOS 指引）与 `项目瘦身优化清单.md`（进一步压缩包体）。
