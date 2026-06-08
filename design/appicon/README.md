# MyFavor AppIcon 设计

## 文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `01-seal.svg` / `.png` | 印章风 | 圆形印章 + 礼字 + 自字私印 |
| `02-cycle.svg` / `.png` | 循环风 | 双箭头循环 + 中央礼字 |
| `03-book.svg` / `.png` | 账本风 | 立体账本 + 礼字 + 金色书签 |
| `preview.html` | 浏览器预览 | 打开后看 3 个设计 + iOS 主屏模拟 |

## 配色规范

| 角色 | 颜色 | 用途 |
|---|---|---|
| 主墨绿 | `#1A3D2E` | 文字、深色背景 |
| 亮墨绿 | `#2C5F4F` | 背景渐变上端 |
| 极墨绿 | `#0F2A1F` | 背景渐变下端 |
| 琥珀 | `#F5E6D3` | 印章/账本封面主色 |
| 浅琥珀 | `#FBEFD8` | 封面高光 |
| 深琥珀 | `#E8D4B5` | 封面阴影 |
| 金色 | `#F2B53C` | 强调(书签、强调元素) |
| 深金 | `#D49B1F` | 渐变下端 |

## 使用步骤

### 方法 A:用 SVG 直接生成 PNG(推荐)

1. 用 **Figma**(免费)打开 `*.svg` 文件
2. **重要**:选中所有文字 → 鼠标右键 → `Convert to Outlines` / `轮廓化文字`
   - 这样做字体独立,避免在 macOS / Windows / iOS 渲染不一致
3. File → Export → PNG → 1024×1024
4. 替换 `MyFavor/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

### 方法 B:用 sharp 命令行(已生成 PNG)

```bash
cd design/appicon
# 已生成 3 个 1024x1024 PNG,可直接用作 iOS AppIcon
# ⚠️ 注意:PNG 中的文字是渲染为位图的,不能再编辑
```

### 方法 C:Sketch / Illustrator

1. 打开 SVG
2. 转曲文字(Type → Convert to Outlines)
3. 导出 PNG 1024×1024

## iOS 配置

Xcode 项目里已经配置好 `AppIcon.appiconset`,只需:

1. 把生成的 `AppIcon.png` (1024×1024) 替换到:
   ```
   MyFavor/Assets.xcassets/AppIcon.appiconset/AppIcon.png
   ```
2. Xcode 编译时会自动生成所有需要的尺寸:
   - iPhone: 180×180, 120×120, 60×60
   - iPad: 167×167, 152×152, 76×76, 40×40
   - Notification: 60×60, 40×40, 20×20
   - App Store: 1024×1024

## 我的推荐

| 场景 | 推荐设计 |
|---|---|
| **主推国内** | 设计 1 (印章风) — 中文用户一眼可识别 |
| **面向年轻用户** | 设计 2 (循环风) — 抽象现代,适合 25-35 岁 |
| **App Store 推荐位展示** | 设计 3 (账本风) — 立体感强,缩略图辨识度最高 |
| **不确定** | 设计 1 (印章风) — 最稳,文化感+通用性平衡 |

## 设计原则

- ✅ 单色块 + 1 个主元素 — 小尺寸依然清晰
- ✅ 高对比度 — 墨绿/琥珀 在深色/浅色模式下都好看
- ✅ 不用 emoji — emoji 在不同系统渲染差异大
- ✅ 无透明 — iOS AppIcon 不支持透明背景
- ✅ 1024×1024 — 满足 App Store 上架规范
