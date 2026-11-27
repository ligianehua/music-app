# 刷歌 · Shuage

像刷短视频一样刷歌：打开就播，一首歌一屏，上滑换一首，双击红心。
玩法参照 QQ 音乐、汽水音乐的竖滑听歌流，调研见 [docs/01-刷歌玩法调研.md](docs/01-刷歌玩法调研.md)。

## 功能

| 交互 | 行为 |
|---|---|
| 上滑 / 下滑 | 下一首 / 回到上一首（回听会被记为加分） |
| 单击 | 暂停 / 继续 |
| 双击 | 红心（只加不减）+ 爆心动画 + 震动 |
| 右侧栏 | 喜欢、心得（本机笔记）、分享（复制文案）、不感兴趣（屏蔽歌手） |
| 底部 | 推荐理由、歌名歌手、可拖动进度条 |
| 顶部 | 口味画像（可重置）、我喜欢歌单（点歌插到下一首） |

- **原生播放队列**：刷歌流里的歌都排在系统原生播放器的队列里。播完一首由系统自己接下一首，不经过 App 代码，锁屏、熄屏时照样无缝连播。加载失败的歌会被自动跳过。
- **不断粮**：每次搜歌没用上的结果会留作备用。网络出错或搜不到新歌时，直接从备用里出歌。
- **锁屏和通知栏**：锁屏显示封面、歌名和进度，可以播放暂停、上一首、下一首、拖动进度。安卓通知栏额外有红心按钮。耳机线控和蓝牙按键同样可用。
- **零等待**：下一首由原生播放器提前缓冲。
- **隐式反馈推荐**：秒划、半途划走、听完、回听、红心、不感兴趣分别加减分，按「歌手全额、风格半额」累计。
- **防信息茧房**：固定 20% 流量用于探索，同一批最多 2 首同歌手，每张卡片都写明推荐理由。
- **歌词**：来自 LRCLIB。播放整首歌时逐行同步；播放试听片段时无法对齐时间，面板停在估算的副歌位置。

## 运行

需要 Flutter 3.50 或更新版本。

```bash
flutter pub get
```

```bash
flutter run
```

真机或模拟器会直接请求 iTunes 曲库，需要联网。没有网络时可以用离线演示模式预览界面，歌曲是占位数据，播放进度由计时器模拟：

```bash
flutter run -d chrome --dart-define=SHUAGE_DEMO=true
```

## 平台配置说明

- **安卓**：入口 Activity 继承自 audio_service 的 Activity，锁屏后 Flutter 引擎由播放服务托管，Dart 代码继续运行。清单里声明了媒体播放类前台服务和媒体按键接收器。
- **iOS**：Info.plist 开启了后台音频。

## 测试

```bash
flutter analyze
```

```bash
flutter test
```

## 结构

```
lib/
  models/track.dart            歌曲模型，含 iTunes 字段映射
  data/
    track_source.dart          音源接口：换曲库只换这里
    itunes_source.dart         iTunes Search API，30 秒试听
    lyrics_source.dart         LRCLIB 歌词
    library_store.dart         本机存储：红心、口味画像、心得
  recommend/
    taste_profile.dart         信号定义与口味打分
    recommender.dart           80% 投其所好 + 20% 探索
  audio/
    audio_engine.dart          播放队列接口，以及区分「自动换歌」和「跳转回声」的判定
    just_audio_engine.dart     just_audio 原生队列实现
    now_playing.dart           系统媒体会话接口：推送状态、接收锁屏指令
    system_media_session.dart  audio_service 实现：锁屏、通知栏、线控
  feed/feed_controller.dart    刷歌流状态机：翻页、计分、续播、拉下一批
  lyrics/                      LRC 解析、副歌估算
  ui/                          主页、单屏卡片、歌词、红心动画、各类弹层
  demo/demo_mode.dart          离线演示模式
```

## 已知限制

- **只有 30 秒试听**。iTunes 不提供完整歌曲，接入正版全曲需要实现新的音源，并给歌曲填入高潮起播点。
- **试听片段的歌词不同步**。iTunes 不告诉片段在原曲中的偏移量。
- **iOS 锁屏没有红心按钮**。audio_service 在 iOS 上禁用了「喜欢」指令，红心只在安卓通知栏提供。
- **长时间断网会停**。试听音频是在线播放的，备用歌也需要联网才能播。断网时 iOS 可能挂起 App，恢复网络后需要回到 App 继续。离线缓存还没做。
- **心得只存在本机**。纯前端 Demo 没有服务器。
