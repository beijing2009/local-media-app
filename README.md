# 本地影音（Local Media）

纯本地运行的跨端影音 App（**Android + iOS**），不依赖任何云端服务器。包含两大独立模块：

- **视频区**：抖音风格上下滑动浏览本地 mp4，自动续播。
- **音频区（听书）**：喜马拉雅风格专辑 / 剧集管理，后台播放、倍速、上下集、进度记忆。

> 所有视频 / 音频读取、播放进度记录 **全部保存在本机**，App 不含任何网络请求代码、不申请 `INTERNET` 权限、不上传任何文件。

---

## 一、技术选型与体积策略

| 维度 | 选择 | 理由 |
|------|------|------|
| 框架 | **Flutter 3.0**（原生编译） | 单代码库跨端，编译为原生机器码，无 JS 桥接；引擎基础包小（APK 约 4–6MB 起） |
| UI | **仅用 Flutter 内置 Material 组件** | 不引入任何大体积第三方 UI 框架（无 GetX UI 库 / 无成熟组件库） |
| 视频 | `video_player` | 直接封装系统 ExoPlayer / AVPlayer，体积小、性能好 |
| 音频 | `audioplayers` | 轻量，支持倍速 / 后台 / 进度 |
| 存储 | `sqflite` + `shared_preferences` | 本地 SQLite 存进度与专辑，无云端 |
| 状态 | `provider` | 极小（数十 KB） |

依赖总数少、均为原生桥接层，已开启 R8 压缩 + 资源裁剪（见下方打包章节）。

---

## 二、功能对照（需求 → 实现）

| 需求 | 实现位置 |
|------|----------|
| 本地文件浏览、识别 mp4/mp3/m4a、浏览文件夹 | `services/file_scanner.dart`、`screens/file_browser_screen.dart` |
| 文件名搜索 | `video_feed_screen`（视频）/ `audio_home_screen`（音频）搜索框 |
| 深色 / 浅色一键切换 | `providers/theme_provider.dart` + `screens/settings/settings_screen.dart` |
| 三独立板块（视频区 / 音频区 / 功能区）互不干扰 | `screens/tabs_screen.dart` 用 `IndexedStack` 保活各页 |
| 视频：抖音式上下滑、暂停、音量 | `screens/video/video_feed_screen.dart`、`video_page.dart` |
| 视频：进度记忆续播 | `video_page.dart` + `services/database_service.dart`（`vp:` 键值） |
| 视频：仅处理视频 | `FileScanner` 只收集 mp4 |
| 音频：自建专辑 / 剧集分类 | `audio_home_screen.dart`（从文件 / 文件夹新建专辑） |
| 音频：每集进度 + 上次剧集记忆 | `audio_provider.dart` + `ap:` / `last_album` 键值 |
| 音频：分栏（剧集列表 / 目录 / 简介） | `album_detail_screen.dart`（宽屏左右分栏，窄屏 Tab 切换） |
| 音频：后台播放 / 倍速 / 上下集 / 音量 | `audio_provider.dart` + `album_detail_screen._ControlPanel` |
| 音频：仅处理音频 | `FileScanner` 只收集 mp3/m4a |
| 性能 / 体积 / 无网络 | 无网络代码、`minifyEnabled`、`shrinkResources`、精简动画 |

---

## 二·五、M3U8 + TS 合并工具（本地）

入口：**功能区 → 本地工具 → M3U8 / TS 合并**。全部在本地完成，**没有任何网络请求**。

### 支持范围

| 场景 | 支持情况 |
|------|----------|
| 明文 TS 分片 | ✅ 按播放顺序直接拼接 |
| `AES-128` / `192` / `256`（按密钥长度自动适配） | ✅ 需密钥已在本机 |
| 显式 `IV=0x...` | ✅ |
| 无 IV（隐式推导） | ✅ 按 **媒体序列号**（`EXT-X-MEDIA-SEQUENCE`）推导，符合 HLS 规范 |
| 密钥文件为**二进制** | ✅ 16 / 24 / 32 字节 |
| 密钥文件为**十六进制文本** | ✅ 32 / 48 / 64 位 hex，容错换行与空格 |
| 密钥 URI 含 `%20` 等编码 | ✅ 自动解码后定位本机文件 |
| 分段换密钥（多个 `EXT-X-KEY`） | ✅ 逐标签生效 |
| 分片缺失 | ✅ 跳过并计数，报告中提示数量 |
| **不支持**：`SAMPLE-AES`、Widevine / FairPlay / PlayReady 等 DRM | ❌ 明确标记为不可读，禁止合并，**不会产出半损坏文件** |
| **不支持**：联网拉取远程分片或密钥 | ❌ 远程资源一律计为缺失 |

### 批量操作
- 列表支持**全选 / 反选 / 清空**，可一次合并多个播放列表并显示进度
- 输出命名二选一：**使用原文件名**（`playlist.ts`）或**按时间自动命名**（`merged_20261004_063012.ts`）
- 合并输出目录会自动加入扫描范围，产物立刻可在**视频区**播放（已支持 `ts` 格式）

### 正确性保障
`test/m3u8_service_test.dart` 提供 **12 个单元测试**（`flutter test` 全绿），覆盖：
明文拼接、显式 IV、隐式 IV + 序号偏移、缺失分片、主列表识别、DRM 拒绝、远程密钥拒绝、
时间命名、批量合并进度、hex 文本密钥、`%` 编码 URI、AES-256 密钥长度。

> ⚠️ 边界原则：**宁可拒绝合并，也不输出一个打不开的假成功文件**。密钥缺失、加密方式不支持
> 时，UI 会禁用勾选，Service 层也会二次拦截并返回失败原因。

---

## 二·六、全盘自动扫描（安卓）

视频区、音频区、M3U8 合并工具都新增了「全盘扫描 / 扫描所有目录」入口（存储图标或菜单项），
一键遍历整个存储根，把散落在各处的媒体一次性找出来，**无需逐个添加目录**。

| 入口 | 行为 |
|------|------|
| 视频区「全盘扫描」 | 扫描全盘 mp4 / ts 视频，自动导入（走「批量导入」管线，可在导入中心管理） |
| 音频区「全盘扫描」 | 按存储根下的一级 / 二级目录自动归并为专辑 |
| M3U8 合并「扫描所有目录」 | 全盘找出所有 `.m3u8`，直接可勾选合并 |

实现要点：
- 扫描在**独立 Isolate** 中执行，不阻塞界面；弹窗实时显示「已扫描目录数 / 已发现文件数」
- 自动跳过 `.thumbnails` / `node_modules` / `lost+found` 等无媒体且遍历成本极高的系统目录
- 需要「所有文件访问」权限（`MANAGE_EXTERNAL_STORAGE`），首次会引导在系统设置中开启
- 全程**零网络请求**

> iOS 限制：受系统沙盒隔离，无法遍历全盘，因此 iOS 不展示上述入口，仍用「文件 App 选目录」导入。

---

## 三、环境准备

- **Flutter SDK ≥ 3.0**（本项目在 Flutter 3.0.0 / Dart 2.17 下开发并 `flutter analyze` 通过）
- Android 构建需要 **Android SDK**（含 build-tools、platform 33）+ **JDK 17**
- iOS 构建需要 **macOS + Xcode 14+**（仅能在 Mac 上出包）

> ⚠️ **关键版本约束（踩坑点）**：本项目用 Gradle 7.4，必须使用 **JDK 17**（JDK 18/20 会报 `Unsupported class file major version`）。`compileSdkVersion` 已设为 **33**（视频播放器底层 ExoPlayer 2.18.5 要求 ≥ 33）。

### 3.1 零基础搭建安卓构建环境（实测可复现）

如果本机还没有 Android SDK / 合适 JDK，按以下步骤一次性装好（Linux/macOS）：

```bash
# ① 安装 JDK 17（示例用 Azul Zulu，可换成 Adoptium/Temurin 等）
#    macOS: brew install --cask zulu@17    Linux: 用系统包管理或下载 tar.gz 解压
export JAVA_HOME=/path/to/jdk-17
export PATH=$JAVA_HOME/bin:$PATH

# ② 下载 Android commandline-tools 并解压
mkdir -p ~/Android/Sdk/cmdline-tools && cd ~/Android/Sdk/cmdline-tools
curl -LO https://dl.google.com/android/repository/commandlinetools-<系统>-9477386_latest.zip
unzip 命令解压到 latest/ 目录

# ③ 安装 SDK 组件（本项目所需）
export ANDROID_HOME=~/Android/Sdk
sdkmanager --sdk_root=$ANDROID_HOME "platform-tools" \
  "platforms;android-31" "platforms;android-33" \
  "build-tools;33.0.1" "ndk;21.1.6352462"
sdkmanager --sdk_root=$ANDROID_HOME --licenses   # 一路 y 接受

# ④（可选/国内网络）Gradle 官方源下载慢时，把
#    android/gradle/wrapper/gradle-wrapper.properties 的 distributionUrl
#    改为阿里云镜像：
#    https\://mirrors.aliyun.com/macports/distfiles/gradle/gradle-7.4-all.zip
```

### 3.2 拉起项目

```bash
# 1) 安装依赖
flutter pub get

# 2) 静态检查（已通过，零告警）
flutter analyze
```

---

## 四、安卓 APK 打包

### 1. 调试 / 直接运行
```bash
flutter run            # 连接真机或模拟器
flutter build apk --debug
```

### 2. 发布版 APK（已开启压缩）
```bash
# 生成按 ABI 拆分的更小安装包（推荐分发）
flutter build apk --release --split-per-abi
# 产物位于：build/app/outputs/flutter-apk/app-<abi>-release.apk
```
`android/app/build.gradle` 已配置：
```gradle
release {
    signingConfig signingConfigs.debug   // 替换为下方正式签名
    minifyEnabled true                   // R8 代码压缩
    shrinkResources true                 // 资源裁剪
    proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
}
```

### 3. 正式签名（上架 / 分发）
```bash
# 生成签名密钥
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
新建 `android/key.properties`：
```
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=upload
storeFile=/绝对路径/upload-keystore.jks
```
在 `android/app/build.gradle` 顶部 `android {` 之前加入：
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```
并修改 `buildTypes.release`：
```gradle
release {
    signingConfig signingConfigs.release
}
```
同时在 `android { defaultConfig { ... } }` 同级增加：
```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
```

### 4. 上架 Google Play（更小分发体积）
```bash
flutter build appbundle --release   # 生成 .aab，Play 按设备动态下发
```

---

## 五、iOS 打包指引（需在 macOS 上操作）

> ⚠️ iOS 安装包只能由 **macOS + Xcode** 编译（Linux 无法出 iOS 包）。
> 本项目已补齐 `ios/Podfile`、将 deployment target 升到 12.0、配置好后台音频与文件共享，
> 并附带 **GitHub Actions 云构建工作流**（`.github/workflows/ios-build.yml`）——
> 推送到 GitHub 后可在其 macOS runner 上**自动产出 IPA**，无需自备 Mac。详见 **`iOS_BUILD.md`**。

### 方式 A：GitHub 云端自动出包（无 Mac 也能拿 IPA）
把项目推到 GitHub 仓库 → **Actions → Build iOS IPA → Run workflow** → 下载 Artifacts 中的 `ios-ipa`。
默认生成未签名 IPA（可用 AltStore 侧载或本地重签）；工作流内已附「已签名」步骤说明。

### 方式 B：本地 Mac 出包
1. 用 Xcode 打开工程：
   ```bash
   open ios/Runner.xcworkspace
   ```
2. 选择 `Runner` Target：
   - **Bundle Identifier** 改为你自己的（如 `com.localmedia.app`，已预置）
   - 选择 **Team**（需 Apple Developer 账号）
   - **Deployment Target** 建议 ≥ 12.0（兼容更多设备）
3. 已在 `ios/Runner/Info.plist` 配置：
   - `UIBackgroundModes: audio` —— 后台 / 锁屏持续播放
   - `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` —— 可通过“文件”App 导入本地媒体
4. 编译发布包：
   ```bash
   flutter build ios --release
   ```
5. 上架 / 内测：
   - Xcode 菜单 **Product → Archive** → 通过 **Organizer** 上传 **App Store / TestFlight**
   - 真机自测：`flutter run` 或 Xcode 直接运行到设备
6. 注意 iOS 沙盒限制：App 不能直接遍历整个文件系统，请通过
   - **文件 App**（开启文件共享后把媒体“存入本地影音”）
   - 或在 App 内用“+”从文件 / 文件夹导入音频 / 视频
   来把媒体加入应用。

---

## 六、代码结构

```
lib/
├── main.dart                     # 入口：注入 Theme/Audio/Scan 三个全局 Provider
├── models/
│   ├── media_file.dart           # 媒体文件模型 + 支持格式
│   └── album.dart               # 音频专辑模型
├── services/
│   ├── permission_service.dart   # 安卓存储权限（MANAGE_EXTERNAL_STORAGE）
│   ├── file_scanner.dart         # 递归扫描 mp4/mp3/m4a
│   └── database_service.dart     # SQLite：进度 / 专辑 / 扫描根目录
├── providers/
│   ├── theme_provider.dart       # 深 / 浅色
│   ├── audio_provider.dart       # 音频播放状态（全局单例）
│   └── scan_notifier.dart        # 扫描源变更通知
├── utils/format.dart             # 时长 / 大小格式化
└── screens/
    ├── tabs_screen.dart          # 三板块 IndexedStack
    ├── file_browser_screen.dart  # 文件夹浏览
    ├── video/
    │   ├── video_feed_screen.dart# 抖音式竖向 PageView
    │   └── video_page.dart       # 单视频页（播放/续播/音量）
    ├── audio/
    │   ├── audio_home_screen.dart# 专辑列表 + 新建
    │   ├── album_detail_screen.dart # 分栏详情 + 控制面板
    │   └── now_playing_bar.dart  # 底部迷你播放条
    └── settings/
        └── settings_screen.dart  # 功能区：外观 / 扫描目录 / 清进度
```

---

## 七、权限与隐私

- **Android**：仅申请 `READ/WRITE_EXTERNAL_STORAGE`（旧版本）与 `MANAGE_EXTERNAL_STORAGE`（Android 11+ 全量文件访问）。**不申请 `INTERNET`**。
- **首次进入视频区**会自动请求存储权限；拒绝后可在「功能区」用文件夹选择器手动指定目录。
- 播放进度、专辑数据全部存于 App 私有数据库（`local_media.db`），**不上传、不联网**。

---

## 八、已知限制与可选增强

- 后台音频：当前基于 `audioplayers` 可在切后台 / 锁屏后继续播放（已配置 iOS `audio` 后台模式）。
  若需 **锁屏媒体控制（播放/暂停/上下集）+ 通知栏常驻**，建议后续接入 `audio_service` + `just_audio`（会略微增加包体，见瘦身清单权衡）。
- iOS 文件系统受限，媒体需通过“文件”App 或 App 内导入，无法像 Android 一样全盘扫描。
- 视频区在启动时会扫描扫描源，目录过大时建议仅添加具体子目录以加快速度。

---

详见同目录 **`项目瘦身优化清单.md`** 获取进一步压缩包体的步骤。
