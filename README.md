# MyFavor — 人情账簿(iOS + 邮箱云同步)

自己开发 [人情账簿]的开源版本。

**核心特性**:邮箱 Magic Link 一键登录 → 数据加密同步到自建后端 → 跨设备无缝继续

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
                                     │ SQLite/Postgres │
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

#### 2. 部署到 Render(免费)

详见后文「免费部署」章节。

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

## 🆓 完全免费组合(零月费)

| 服务 | 用途 | 免费额度 | 是否够用 |
|---|---|---|---|
| **Render** | 后端托管 | 750 小时/月 | ✅ 单 App 用不完 |
| **Neon** | PostgreSQL | 0.5 GB,100 项目 | ✅ 个人项目随便用 |
| **Resend** | 发登录邮件 | 3000 封/月 | ✅ 1000 用户每月登 3 次刚够 |
| **Apple ID** | 模拟器开发 | 免费 | ✅ 学习/自用 |
| **域名(可选)** | 专业邮箱发件 | ¥60/年 | 上线时再买 |

**完全免费组合一年:¥0~70**(可选买域名)

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

## 📄 License

MIT
