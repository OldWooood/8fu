# 八福播放器 (8fu Player)

一个简洁、高效的本地音频播放器，专为 Android 平台设计。它能快速索引并播放您指定文件夹内的音频文件，支持数字快捷键选曲，是您管理和收听本地音频集的理想选择。

## 核心特性

- **高效索引**: 首次启动后，应用会自动扫描并高效缓存您的音频列表（使用 Hive），后续启动无需等待，即刻加载。
- **数字选曲**: 通过界面下方的数字键盘快速输入曲目编号，在您停止输入的片刻后，应用便会自动跳转到您想听的歌曲。
- **播放记忆**: 自动记住您上次播放的歌曲和选择的循环模式，下次打开应用即可继续收听。
- **两种循环模式**: 支持“列表循环”和“单曲循环”，满足不同收听需求，操作直观。
- **简洁界面**: 清晰展示歌曲标题、总曲目数、当前播放序号和进度。长标题会优雅地截断显示，避免界面混乱。
- **性能优先**: 采用高效的本地缓存和优化的 UI 策略，确保应用运行流畅且节省电量。

## 使用指南

1.  **首次启动**: 应用会自动请求文件访问权限。授权后，它会在您的设备根目录创建一个名为 `8fu` 的文件夹。
2.  **添加音频**: 请将您的音频文件（支持 `.mp3`, `.wav` 等格式）放入 `8fu` 文件夹下的**子文件夹**中。应用会按照子文件夹名称和文件名的字典序进行排序。
3.  **开始播放**: 应用会自动加载音频列表。您可以通过“上一首”、“下一首”或数字键盘来选择和播放歌曲。

## 构建与打包

本项目使用 Flutter 构建。

若要打包发布版 (Release) APK，您需要在 `android/` 目录下配置您的应用签名信息。

1.  在 `android/` 目录下，创建一个名为 `key.properties` 的文件。
2.  在该文件中，填入您的密钥库信息，格式如下：

    ```properties
    storeFile=/path/to/your/keystore.jks
    storePassword=your_store_password
    keyAlias=your_key_alias
    keyPassword=your_key_password
    ```

3.  运行 `flutter build apk --release` 来生成已签名的 APK 文件。

## 技术栈

- **核心框架**: [Flutter](https://flutter.dev/)
- **本地缓存**: [Hive](https://pub.dev/packages/hive)
- **状态记忆**: [SharedPreferences](https://pub.dev/packages/shared_preferences)
- **音频播放**: [audioplayers](https://pub.dev/packages/audioplayers)
- **权限管理**: [permission_handler](https://pub.dev/packages/permission_handler)
