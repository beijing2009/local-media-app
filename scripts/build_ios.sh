#!/usr/bin/env bash
# 在 macOS 上构建 iOS 安装包（需已安装 Xcode + CocoaPods + Flutter 3.0）
# 用法：bash scripts/build_ios.sh
set -e

echo "==> flutter pub get"
flutter pub get

echo "==> pod install"
cd ios
pod install --repo-update
cd ..

echo "==> flutter build ipa --release"
# 未配置签名时先用 --no-codesign 生成未签名 IPA（用 Xcode/AltStore 重签后可装真机）
flutter build ipa --release --no-codesign

echo "==> 完成，IPA 位于 build/ios/ipa/"
ls -lh build/ios/ipa/
