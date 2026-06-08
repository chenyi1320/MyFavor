// MyFavor Magic Link routes
//   POST /auth/magic/send    — 发送验证码邮件
//   POST /auth/magic/verify  — 用 code 或 token 换 JWT
//   GET  /auth/magic/open    — 邮件链接点击的落地页(deep link 回 App)
import { Router } from 'express';
import crypto from 'crypto';
import { prisma } from '../lib/prisma.js';
import { signJWT } from '../lib/jwt.js';
import { sendMagicLinkEmail, APP_NAME, APP_URL_SCHEME } from '../lib/email.js';

export const magicRoutes = Router();

// === HTML 转义工具(防止 APP_NAME 等环境变量注入) ===
function escHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!)
  );
}

// === 配置 ===
const CODE_LENGTH = 6;
const CODE_EXPIRY_MIN = 15;        // 15 分钟
const RATE_PER_EMAIL_PER_MIN = 1;  // 同邮箱 1 分钟 1 次
const RATE_PER_EMAIL_PER_DAY = 10; // 同邮箱 1 天 10 次
const RATE_PER_IP_PER_HOUR = 20;   // 同 IP 1 小时 20 次

// === 辅助 ===
function isValidEmail(s: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}
function genCode(): string {
  // 6 位数字(100000-999999),用密码学安全随机
  // Math.random() 是非密码学 PRNG,xorshift128+ 可被预测 → 验证码可被绕过
  return String(crypto.randomInt(100000, 1000000));
}
function genToken(): string {
  return crypto.randomBytes(32).toString('hex'); // 64-char
}

// ============================================================
// POST /auth/magic/send
//   Body: { email: "user@example.com" }
//   Resp: { ok: true, expires_in: 900 }
// ============================================================
magicRoutes.post('/send', async (req, res, next) => {
  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    const ip = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
               || req.socket.remoteAddress || '';
    const ua = String(req.headers['user-agent'] || '').slice(0, 200);

    if (!isValidEmail(email)) {
      return res.status(400).json({ error: '邮箱格式不正确' });
    }

    // ---- 限频:并行 3 个时段 count(只查必要的时间窗) ----
    const oneMinuteAgo = new Date(Date.now() - 60_000);
    const oneDayAgo = new Date(Date.now() - 24 * 3600_000);
    const oneHourAgo = new Date(Date.now() - 3600_000);

    const [recentByEmail, dayByEmail, hourByIp] = await Promise.all([
      prisma.magicToken.count({ where: { email, createdAt: { gt: oneMinuteAgo } } }),
      prisma.magicToken.count({ where: { email, createdAt: { gt: oneDayAgo } } }),
      ip
        ? prisma.magicToken.count({ where: { ip, createdAt: { gt: oneHourAgo } } })
        : Promise.resolve(0),
    ]);

    if (recentByEmail >= RATE_PER_EMAIL_PER_MIN) {
      return res.status(429).json({ error: '请求过于频繁,请 1 分钟后再试' });
    }
    if (dayByEmail >= RATE_PER_EMAIL_PER_DAY) {
      return res.status(429).json({ error: '今日发送已达上限' });
    }
    if (ip && hourByIp >= RATE_PER_IP_PER_HOUR) {
      return res.status(429).json({ error: '请求过于频繁' });
    }

    // ---- 生成 token + code ----
    const token = genToken();
    const code = genCode();
    const expiresAt = new Date(Date.now() + CODE_EXPIRY_MIN * 60_000);

    // ---- 先发邮件,成功后再写库 ----
    // 避免:发邮件失败时数据库已落记录,用户重试被限频挡掉
    await sendMagicLinkEmail({ to: email, token, code });

    await prisma.magicToken.create({
      data: { email, token, code, expiresAt, ip, userAgent: ua },
    });

    return res.json({
      ok: true,
      expires_in: CODE_EXPIRY_MIN * 60,
      message: `验证码已发送到 ${email}`,
    });
  } catch (err: any) {
    // 只记录错误码/状态,不打印 message(可能含邮箱/token)
    console.error('[Magic Send] error code:', err?.code, 'status:', err?.httpStatus ?? err?.statusCode);

    // === 邮件服务错误(Resend 上游)→ 返回 502,不归为系统 500 ===
    if (err?.code === 'EMAIL_SEND_FAILED' || err?.httpStatus === 502) {
      return res.status(502).json({
        error: err.message,
        code: 'EMAIL_SEND_FAILED',
        hint: '邮件服务异常,通常是 Resend 免费版限制(只能发到注册邮箱)或 API Key 失效',
      });
    }

    // === Prisma / 数据库错误 → 保留默认 500,便于排查 ===
    next(err);
  }
});

// ============================================================
// POST /auth/magic/verify
//   Body: { email, code }   或   { token }
//   Resp: { token: jwt, user, expires_at }
// ============================================================
magicRoutes.post('/verify', async (req, res, next) => {
  try {
    const { email, code, token } = req.body || {};

    if (!token && !(email && code)) {
      return res.status(400).json({ error: '需要 token 或 (email + code)' });
    }

    // 校验 code 格式(必须是 6 位数字,避免任意字符串查询浪费索引)
    if (code !== undefined && !/^\d{6}$/.test(String(code).trim())) {
      return res.status(400).json({ error: '验证码格式不正确' });
    }
    if (token !== undefined && (typeof token !== 'string' || token.length < 16)) {
      return res.status(400).json({ error: 'token 格式不正确' });
    }

    // 查 MagicToken
    let mt = null as Awaited<ReturnType<typeof prisma.magicToken.findUnique>> | null;
    if (token) {
      mt = await prisma.magicToken.findUnique({ where: { token: String(token) } });
    } else {
      const eml = String(email).trim().toLowerCase();
      const cd = String(code).trim();
      mt = await prisma.magicToken.findFirst({
        where: { email: eml, code: cd, usedAt: null },
        orderBy: { createdAt: 'desc' },
      });
    }

    if (!mt) {
      return res.status(401).json({ error: '验证码无效或已被使用' });
    }
    if (mt.usedAt) {
      return res.status(401).json({ error: '验证码已被使用' });
    }
    if (mt.expiresAt < new Date()) {
      return res.status(401).json({ error: '验证码已过期,请重新获取' });
    }

    // === 事务包裹:原子操作 + 用户 upsert ===
    // 1. 原子标记 token 已用(防 TOCTOU 并发双花)
    // 2. upsert user(过滤已删除账户,不复活)
    const user = await prisma.$transaction(async (tx) => {
      const claimed = await tx.magicToken.updateMany({
        where: {
          id: mt!.id,
          usedAt: null,
          expiresAt: { gt: new Date() },
        },
        data: { usedAt: new Date() },
      });
      if (claimed.count === 0) {
        throw new Error('TOKEN_ALREADY_USED');
      }
      // 显式过滤 deletedAt:不允许"软删账户被任意新验证码复活"
      const existing = await tx.user.findUnique({ where: { email: mt!.email } });
      if (existing && existing.deletedAt != null) {
        // 已删除账户,拒绝重新激活(用户需走"恢复账户"流程)
        throw new Error('ACCOUNT_DELETED');
      }
      if (existing) {
        return tx.user.update({
          where: { id: existing.id },
          data: { lastLoginAt: new Date() },
        });
      }
      return tx.user.create({
        data: {
          email: mt!.email,
          name: mt!.email.split('@')[0],
          lastLoginAt: new Date(),
        },
      });
    });

    // 在事务外签 JWT(避免 token 签发占用事务连接)
    const { token: jwtToken, expiresAt: jwtExpires } = signJWT({ sub: user.id });

    return res.json({
      token: jwtToken,
      expires_at: jwtExpires.toISOString(),
      user: {
        id: user.id,
        name: user.name || '',
        email: user.email || null,
      },
    });
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === 'TOKEN_ALREADY_USED') {
      return res.status(401).json({ error: '验证码已被使用' });
    }
    if (msg === 'ACCOUNT_DELETED') {
      return res.status(403).json({ error: '账户已注销,无法登录' });
    }
    next(err);
  }
});

// ============================================================
// GET /auth/magic/open?token=xxx
//   邮件链接点击进入的落地页 — 自动 deep link 回 App
// ============================================================
magicRoutes.get('/open', (req, res) => {
  const token = String(req.query.token || '');
  if (!token) return res.status(400).send('Missing token');

  // deepLink 用 JSON.stringify 转义(JS 字符串字面量安全),不在 HTML 属性里直接拼
  const deepLink = `${APP_URL_SCHEME}://magic?token=${encodeURIComponent(token)}`;
  const safeApp = escHtml(APP_NAME);

  const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>${safeApp} · 正在打开</title>
<style>
  body { margin:0; padding:0; font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif;
         background: #FAF8F4; min-height: 100vh;
         display: flex; align-items: center; justify-content: center; color: #2C3E2D; text-align: center; }
  .card { background: #FFFFFF; padding: 40px 32px; border-radius: 16px;
          max-width: 360px; border: 1px solid #E8E4DC;
          box-shadow: 0 4px 24px rgba(44,95,79,0.08); }
  .icon { width: 64px; height: 64px; margin: 0 auto 18px;
          background: #F5E6D3; border-radius: 50%;
          display: flex; align-items: center; justify-content: center;
          font-size: 30px; }
  h1 { margin: 0 0 10px; font-size: 20px; font-weight: 600; color: #2C3E2D; letter-spacing: 1px; }
  p  { color: #6B7B6C; line-height: 1.7; font-size: 14px; margin: 6px 0; }
  a  { display:inline-block; background: #2C5F4F; color: #F5E6D3;
       padding: 12px 32px; border-radius: 10px;
       text-decoration: none; font-weight: 500; margin-top: 22px; font-size: 14px; letter-spacing: 1px; }
  .hint { font-size: 12px; color: #A0A0A0; margin-top: 24px; line-height: 1.6; }
</style>
</head>
<body>
  <div class="card">
    <div class="icon">🏮</div>
    <h1>正在打开 ${safeApp}</h1>
    <p>如果 App 没有自动启动,<br/>请使用下方按钮手动打开。</p>
    <a href="${escHtml(deepLink)}">打开 App</a>
    <p class="hint">仍未响应?可在 App 中输入邮件中的 6 位验证码。</p>
  </div>
  <script>
    setTimeout(function(){ window.location.href = ${JSON.stringify(deepLink)}; }, 50);
  </script>
</body></html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
});
