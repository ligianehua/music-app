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

- **自动续播**：试听片段放完自动翻到下一张。
- **零等待**：始终预加载下一首音频。
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
    audio_engine.dart          播放接口
    just_audio_engine.dart     just_audio 实现，播放器池做预加载
  feed/feed_controller.dart    刷歌流状态机：翻页、计分、续播、拉下一批
  lyrics/                      LRC 解析、副歌估算
  ui/                          主页、单屏卡片、歌词、红心动画、各类弹层
  demo/demo_mode.dart          离线演示模式
```

## 已知限制

- **只有 30 秒试听**。iTunes 不提供完整歌曲，接入正版全曲需要实现新的音源，并给歌曲填入高潮起播点。
- **试听片段的歌词不同步**。iTunes 不告诉片段在原曲中的偏移量。
- **锁屏控制和通知栏播放器还没做**。iOS 已开启后台音频；完整的锁屏控制需要接入 audio_service。
- **心得只存在本机**。纯前端 Demo 没有服务器。
