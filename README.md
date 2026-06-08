# MyFavor — 自托管的礼尚往来小本本(iOS + 邮箱云同步)

一款**完全开源**、**自托管**的礼尚往来记账工具。
邮箱 Magic Link 一键登录 → 数据加密同步到你自己的后端 → 跨设备无缝继续。

> 💡 **为什么做这个?**
> 日常生活中"随份子"是高频但易忘的事,需要一款**长期、跨设备、隐私优先**
> 的工具。市面同类 App 大多闭源、强制使用特定账号体系、且服务器端无从审计。
>
> MyFavor 想做的很简单:**你的数据,跑在你自己的服务器上,完全由你掌控**。

---

## ✨ 项目特色

| 特色 | 说明 |
|---|---|
| 🏠 **自托管优先** | 一键脚本部署到阿里云 ECS(详见 [deploy-aliyun-mysql.sh](deploy-aliyun-mysql.sh))|
| 🔐 **邮箱即账号** | 不绑定 Apple / 微信 / 手机号,无强制实名 |
| 🆓 **零运营成本** | 邮箱 Magic Link 替代付费 Apple Developer 能力 |
| 📱 **原生 iOS** | SwiftUI + SwiftData,完全离线优先 |
| 🔄 **冲突合并** | Last-Write-Wins 增量同步,支持任意设备数量 |
| 📖 **MIT 协议** | 代码、协议、数据格式完全开放,可审计、可二次开发 |

---

## ✨ 为什么不用 Sign in with Apple?

- ❌ Sign in with Apple **需要付费 Apple Developer Program($99/年)**
- ✅ 邮箱 Magic Link **完全免费**,且任何邮箱都能用
- ✅ 用户输入邮箱 → 收 6 位验证码或一键链接 → 登录完成
- ✅ 不存密码,免实名认证,免短信审核

---

## 🗂 整体架构

```
┌─────────────────┐  email + code   ┌─────────────────┐  
│ iOS App         │ ──────────────► │ Node.js Backend │
│ SwiftUI+SwiftData│                  │ Express + JWT   │
│                 │ ◄── JWT (30d) ── │ Resend 发邮件   │
└─────────────────┘                  └────────┬────────┘
        │                                     │
        │   邮件回链(myfavor://magic)         │
        └─────────────────────────────────────┘
                                              ↓
                                     ┌─────────────────┐
                                     │ Prisma ORM      │
                                     │ ↓               │
                                     │ MySQL(SQLPub)   │
                                     └─────────────────┘
```

---

## 📦 目录结构

```
MyFavor/                         # iOS 项目(SwiftUI + SwiftData)
├── MyFavor.xcodeproj            
├── MyFavor/
│   ├── MyFavorApp.swift          # @main + 登录路由 + 深度链接(myfavor://magic)
│   ├── ContentView.swift         # 根 Tab
│   ├── Info.plist                # 注册 URL Scheme
│   ├── Models/                   # 4 SwiftData 模型 + Syncable
│   ├── Services/
│   │   ├── KeychainHelper.swift  # JWT 安全存储
│   │   ├── APIClient.swift       # HTTP + 401 自动登出
│   │   ├── AuthService.swift     # 通用身份状态(无 Apple)
│   │   ├── MagicLinkService.swift# 邮箱发码/验码
│   │   └── SyncEngine.swift      # 推+拉,Last-Write-Wins
│   ├── Views/
│   │   ├── Auth/LoginView.swift  # 邮箱输入 + 6 位验证码
│   │   └── ...
│   └── Utilities/
└── backend/                      # Node.js + TypeScript 后端
    ├── package.json
    ├── tsconfig.json
    ├── .env.example
    ├── prisma/schema.prisma      # User / MagicToken / 业务表
    └── src/
        ├── server.ts             # Express 入口
        ├── lib/
        │   ├── prisma.ts
        │   ├── jwt.ts            # 我们自己的 JWT
        │   └── email.ts          # Resend 集成 + 邮件模板
        ├── middleware/
        │   ├── auth.ts           # JWT 中间件
        │   └── error.ts
        └── routes/
            ├── magic.ts          # POST /auth/magic/send + verify + GET open
            ├── sync.ts           # POST /sync/push + GET /sync/pull
            └── account.ts        # GET/DELETE /account
```

---

## 🚀 部署流程

### 一、后端

#### 1. 本地启动

```bash
cd backend

cp .env.example .env
# 编辑 .env:
#   RESEND_API_KEY=re_xxx     从 https://resend.com 获取
#   JWT_SECRET=$(openssl rand -hex 64)

npm install
npx prisma generate
npx prisma migrate dev --name init
npm run dev
# → http://localhost:3000
```

#### 2. 部署到阿里云 ECS

一键脚本(ECS + SQLPub MySQL):见仓库根目录 [`deploy-aliyun-mysql.sh`](deploy-aliyun-mysql.sh)。

CI/CD 通过 GitHub Actions 推送到 ECS(`.github/workflows/deploy.yml`),配置好 `ECS_HOST` / `ECS_USER` / `ECS_SSH_KEY` 三个 Secret 后,推 `main` 分支自动部署。

### 二、iOS

1. 把整个项目拷到 Mac
2. 双击 [MyFavor.xcodeproj](MyFavor.xcodeproj)
3. 选 Target → Signing & Capabilities:
   - **Team:可以用免费 Apple ID**(因为不用任何付费 capability!)
   - **Bundle Identifier**:`com.myfavor.app`
4. 改 [APIClient.swift](MyFavor/Services/APIClient.swift) 的 `baseURL`:
   - Debug:`http://localhost:3000`
   - Release:你的生产域名
5. ⌘R 运行

---

## 🪙 成本估算(按月)

| 服务 | 用途 | 月费 | 说明 |
|---|---|---|---|
| **阿里云 ECS** | 后端托管 | ~¥50 | 最低配 1C1G,学生机可免费 |
| **SQLPub** | MySQL 数据库 | 免费 | 免费版够个人项目;生产可买付费版 |
| **Resend** | 发登录邮件 | 免费 | 3000 封/月,够 1000 用户每月登 3 次 |
| **Apple ID** | 模拟器/真机开发 | 免费 | 自用免开发者账号 |
| **域名(可选)** | 邮件发件域名 | ~¥5/月 | 上线后再买,初期可用 `onboarding@resend.dev` |

**首年成本:~¥60(ECS + 可选域名),可压到 ~¥0(用学生机 + 默认发件人)**

---

## 🔐 登录流程

```
1. 用户输入邮箱   ────────────────►
                                  POST /auth/magic/send
                                          │
                                          ▼
                                  生成 6 位 code + 64 字符 token
                                          │
                                          ▼
                                  Resend 发邮件:验证码 + 链接
                                          │
2. 用户收到邮件 ◄────────────────
                                          
3a. 输入 6 位验证码到 App
    ─────────────────────────►
    POST /auth/magic/verify
    { email, code }
                                  → 校验、签 JWT、返回
                                          │
3b. 或点邮件里的链接(在 App 内打开)
    →  myfavor://magic?token=xxx
    →  iOS 自动打开 App
    →  POST /auth/magic/verify
    { token }
                                  → 同上
4. App 拿到 JWT,存 Keychain,登录完成
```

---

## 🛡️ 安全防护

| 项目 | 实现 |
|---|---|
| 限频:同邮箱 1 分钟 1 条 | `magic.ts` |
| 限频:同邮箱 1 天 10 条 | `magic.ts` |
| 限频:同 IP 1 小时 20 条 | `magic.ts` |
| 验证码 15 分钟过期 | 后端 + 数据库 |
| 验证码一次有效 | `usedAt` 标记 |
| Token 64 字符随机 | `crypto.randomBytes(32)` |
| JWT 30 天过期 | 配置可调 |
| JWT 加密存储 | iOS Keychain |
| 401 自动登出 | `APIClient` |
| 账号删除 | `DELETE /account` |

---

## 📋 已知 TODO

- [ ] 同步进度条 UI
- [ ] 同步冲突手动解决面板
- [ ] iOS 真机推送通知(到期提醒)
- [ ] CloudKit 备用方案
- [ ] 后端单元测试
- [ ] 多语言(英文)

---

## 🙏 致谢与说明

本项目灵感来自日常生活中"礼尚往来"的记账需求——一个**通用且古老的场景**,
在国内外有多个 App 在做(包括但不限于账本类、礼金类应用)。

MyFavor 与上述产品的差异:
- **完全开源** —— 你可以读、改、编译自己用
- **自托管** —— 数据在你自己的服务器上,不经第三方
- **无强制账号体系** —— 用邮箱 Magic Link,免 Apple/微信/手机号绑定
- **协议透明** —— MIT License,数据格式可导出

如果本项目对你有帮助,欢迎 Star / Fork / 提 PR。

---

## 📄 License

MIT
