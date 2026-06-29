# 大魚吃小魚

Flutter 2.5D 海洋生存遊戲原型。玩家從小魚開始成長，吃掉同級或更低級的魚取得經驗，高等掠食魚會造成傷害並可能追擊玩家。

## 目前玩法

- 全螢幕拖曳控制魚的游動方向。
- 玩家共 15 級，每一級使用不同魚種，由小到大。
- 同級或比自己低級的魚可以吃。
- 比自己高級的魚碰到玩家會扣血，部分高級魚會間歇追擊。
- 場上維持 40 隻魚，並依玩家等級生成前後 5 級範圍內的魚。

## 本機測試

```sh
flutter analyze
flutter test
flutter build web
flutter build macos --debug
```

Web 版 build 完後可在 `build/web` 啟動本機伺服器：

```sh
cd build/web
python3 -m http.server 4301 --bind 127.0.0.1
```

然後開啟：

```text
http://127.0.0.1:4301/
```

## 環境限制

這台機器目前沒有 Android SDK，也沒有 Google Chrome，所以 Android APK build 與 Chrome 平台測試無法在本機完成。
macOS debug app 可以成功 build 並啟動；若要做完整視覺自動驗證，需要先完成 Codex Computer Use 的螢幕錄製與輔助使用權限。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
