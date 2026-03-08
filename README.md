# light-fps-operator-demo

这是一个基于 **Godot 4 + GDScript** 的轻量第一人称射击原型项目，用来验证“FPS 射击 + Operator 连锁改写”的玩法框架。

项目已从原始 Unity 版本迁移到 Godot，当前重点是：

- Hub 场景中的购买、库存、装配流程
- Range 场景中的第一人称移动、命中判定、目标重置
- Operator 链对射击参数和命中效果的改写
- 运行时调试面板与本地日志

## 当前功能

- Hub 场景
  - 展示金币、库存、商店、当前 Loadout
  - 支持购买 Operator
  - 支持将 Operator 加入 Loadout
  - 支持调整 Loadout 顺序
- Range 场景
  - WASD 移动
  - 鼠标视角控制
  - 左键射击
  - R 重置目标
  - Esc 释放或锁定鼠标
- 战斗系统
  - 命中采用 hitscan 判定
  - 可见激光弹道与命中闪点
  - 中央绿色准星
  - 屏幕常驻 Debug 面板
  - 本地 `debug.log` 记录输入、开火、命中、重置等信息

## 已实现的 Operator

当前内置 6 个 Operator 资源，位于 `data/operators/`：

1. `Duplicate X2`：将弹丸数量翻倍
2. `Add One`：额外增加一个弹丸
3. `Scatter`：增加散布
4. `Focus`：减小散布
5. `Mark On Hit`：命中时叠加标记
6. `Execute`：消耗标记并附加额外伤害

## 运行方式

### 方式一：直接打开编辑器

运行：

```bat
open_editor.cmd
```

### 方式二：直接启动项目

运行：

```bat
run_project.cmd
```

### 方式三：使用本地便携 Godot 环境

本项目默认配套的本地 Godot 环境位于：

```text
E:\Apps\Godot\4.6.1
```

命令行入口位于：

```text
E:\Apps\Godot\bin\godot4.cmd
E:\Apps\Godot\bin\godot4_console.cmd
```

## 控制说明

- `W` `A` `S` `D`：移动
- `鼠标`：视角控制
- `左键`：射击
- `R`：重置靶子
- `Esc`：切换鼠标锁定状态

## 调试

项目包含双重调试链路：

- 屏幕内 Debug 面板
- 本地日志文件

日志文件位置：

```text
E:\Apps\Godot\data\AppData\Godot\app_userdata\light-fps-operator-demo-godot\debug.log
```

Godot 运行日志：

```text
E:\Apps\Godot\data\AppData\Godot\app_userdata\light-fps-operator-demo-godot\logs\godot.log
```

## 项目结构

```text
data/
  operators/
scenes/
  hub_scene.tscn
  range_scene.tscn
  player.tscn
  target_dummy.tscn
scripts/
  combat/
  core/
  operators/
  player/
  scene/
  ui/
```

## 说明

- 当前仓库以 Godot 版本为主。
- `.godot/` 为编辑器生成目录，不属于核心源码。
- 当前项目目标是先稳定验证玩法框架，再逐步增强表现和系统扩展性。
