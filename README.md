# eightfu

8福播放器

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

一个基于安卓平台的flutter应用，它的功能是一个音频播放器，播放指定路径夹下的音频。
首次启动应用，首先申请存储权限，然后新建一个‘8fu’文件夹，然后提示用户将音频文件放入该文件夹。
界面整体有上下两部分组成，上部分显示当前正在播放的音频名字和对应的音乐序号和进度条，下方是一系列操作按钮：
包含“循环”、“上一曲”，“下一曲”，“播放/暂停”，和0～9的10个数字按键。
当按下数字按键后，上分状态显示区域上会展示示对应的数字，当用户停止继续按键，便播放对应的编号的音频。