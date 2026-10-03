# iOS 构建说明（生成 IPA）

> **重要前提**：iOS 的安装包（`.ipa`）只能由 **macOS + Xcode** 工具链编译并签名。
> 本项目的开发沙箱是 Linux，**无法在本机直接编译 iOS 包**（无 Xcode / darling）。
> 为此，本项目已做到「在任意 Mac 上一键出包」，并附带可在云端 macOS 自动出包的**GitHub Actions 工作流**。

---

## 一、本项目已为你做好的事（iOS 构建就绪）

| 项目 | 状态 | 说明 |
|------|------|------|
| `ios/Podfile` | ✅ 已补齐 | Flutter 3.0 依赖 CocoaPods，缺它无法 `pod install` |
| `IPHONEOS_DEPLOYMENT_TARGET` | ✅ 已设为 12.0 | 原 9.0 过低，插件要求 ≥11 |
| `ios/Runner/Info.plist` | ✅ 已配置 | `UIBackgroundModes: audio`（后台播放）、`UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace`（文件 App 导入） |
| Bundle ID | ✅ `com.localmedia.app` | 可自行在 Xcode 修改 |
| `.github/workflows/ios-build.yml` | ✅ 已提供 | 云端 macOS 自动出 IPA |

---

## 二、方式 A：用 GitHub 云端 macOS 出包（推荐，无需自备 Mac）

1. 把本项目推送到一个 GitHub 仓库（公开仓库可用免费 macOS 额度）。
2. 进入仓库 **Actions → Build iOS IPA → Run workflow**（或在 `main` 分支推送后自动触发）。
3. 运行结束后，在 **Artifacts** 中下载 `ios-ipa`，里面就是 `*.ipa`。
   - 默认是 **未签名 IPA**（`--no-codesign`），可用 **AltStore / Sideloadly** 等侧载，或在你 Mac 上用 Xcode 重新签名后安装。
4. 若需**已签名、可直接上架/真机安装**的 IPA：在仓库 `Settings → Secrets` 配置证书（见工作流文件内注释），并启用签名步骤。

---

## 三、方式 B：本地 Mac 出包

前置：安装 **Xcode 14+**、**CocoaPods**、**Flutter 3.0**。

```bash
cd local_media_app

# 1) 拉取 Flutter 依赖
flutter pub get

# 2) 安装 iOS 原生依赖（必须有 Podfile，已补齐）
cd ios && pod install --repo-update && cd ..

# 3) 出包
flutter build ipa --release            # 已配置签名时
# 或使用脚本（未配置签名时生成未签名 IPA）
bash scripts/build_ios.sh
```

产物位于 `build/ios/ipa/*.ipa`。

### 签名（二选一）
- **开发/自测（免费）**：Xcode 打开 `ios/Runner.xcworkspace` → 选中 Runner → Signing & Capabilities → 选你的 Apple ID（Personal Team）。`flutter build ipa` 会自动用它签名，可直接装到已信任的设备。
- **上架/分发**：Apple Developer 后台创建 Distribution 证书 + Provisioning Profile，配置到 Xcode 或 `exportOptions.plist` 后导出。

---

## 四、安装到 iPhone 验证
- 已签名 IPA：用 Xcode → Devices、Apple Configurator 2、或 TestFlight 安装。
- 未签名 IPA：用 AltStore / Sideloadly 侧载（需同一 Apple ID 信任）。

---

## 五、常见问题

| 现象 | 原因 / 解决 |
|------|-------------|
| `pod install` 报找不到 `Podfile` | 已补齐 `ios/Podfile`，确保从本项目根目录执行 `cd ios && pod install` |
| `requires a minimum deployment target of 11.0` | 已把 deployment target 升到 12.0 |
| 后台不播放 | 确认 `Info.plist` 含 `UIBackgroundModes: audio`（已配置） |
| 文件 App 看不到本 App | 确认 `UIFileSharingEnabled = true`（已配置） |
| Linux 上 `flutter build ios` 失败 | 正常现象：iOS 编译只能在 macOS 上进行，请走方式 A 或 B |

详见 `README.md` 与 `BUILD_ENV_AND_APK.md`。
