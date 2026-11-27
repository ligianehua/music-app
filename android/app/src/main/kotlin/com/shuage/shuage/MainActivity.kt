package com.shuage.shuage

import com.ryanheise.audioservice.AudioServiceActivity

// 继承 AudioServiceActivity：Flutter 引擎由播放服务托管，
// 锁屏或界面被系统回收后 Dart 代码仍在运行，才能自动切下一首。
class MainActivity : AudioServiceActivity()
