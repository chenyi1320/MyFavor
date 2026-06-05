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
  // 6 位数字,首位不为 0
  let s = String(Math.floor(Math.random() * 9) + 1);
  for (let i = 1; i < CODE_LENGTH; i++) {
    s += String(Math.floor(Math.random() * 10));
  }
  return s;
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

    // ---- 限频 1:同邮箱 1 分钟 1 次 ----
    const oneMinuteAgo = new Date(Date.now() - 60_000);
    const recentByEmail = await prisma.magicToken.count({
      where: { email, createdAt: { gt: oneMinuteAgo } },
    });
    if (recentByEmail >= RATE_PER_EMAIL_PER_MIN) {
      return res.status(429).json({ error: '请求过于频繁,请 1 分钟后再试' });
    }

    // ---- 限频 2:同邮箱 1 天 10 次 ----
    const oneDayAgo = new Date(Date.now() - 24 * 3600_000);
    const dayByEmail = await prisma.magicToken.count({
      where: { email, createdAt: { gt: oneDayAgo } },
    });
    if (dayByEmail >= RATE_PER_EMAIL_PER_DAY) {
      return res.status(429).json({ error: '今日发送已达上限' });
    }

    // ---- 限频 3:同 IP 1 小时 20 次(防恶意脚本) ----
    if (ip) {
      const oneHourAgo = new Date(Date.now() - 3600_000);
      const hourByIp = await prisma.magicToken.count({
        where: { ip, createdAt: { gt: oneHourAgo } },
      });
      if (hourByIp >= RATE_PER_IP_PER_HOUR) {
        return res.status(429).json({ error: '请求过于频繁' });
      }
    }

    // ---- 生成 token + code ----
    const token = genToken();
    const code = genCode();
    const expiresAt = new Date(Date.now() + CODE_EXPIRY_MIN * 60_000);

    await prisma.magicToken.create({
      data: { email, token, code, expiresAt, ip, userAgent: ua },
    });

    // ---- 发邮件 ----
    await sendMagicLinkEmail({ to: email, token, code });

    return res.json({
      ok: true,
      expires_in: CODE_EXPIRY_MIN * 60,
      message: `验证码已发送到 ${email}`,
    });
  } catch (err: any) {
    console.error('[Magic Send] error:', err);
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

    // 标记已用
    await prisma.magicToken.update({
      where: { id: mt.id },
      data: { usedAt: new Date() },
    });

    // upsert user
    const user = await prisma.user.upsert({
      where: { email: mt.email },
      create: {
        email: mt.email,
        name: mt.email.split('@')[0],
      },
      update: { lastLoginAt: new Date(), deletedAt: null },
    });

    // sign JWT
    const { token: jwt, expiresAt } = signJWT({ sub: user.id });

    return res.json({
      token: jwt,
      expires_at: expiresAt.toISOString(),
      user: {
        id: user.id,
        name: user.name || '',
        email: user.email || null,
      },
    });
  } catch (err) { next(err); }
});

// ============================================================
// GET /auth/magic/open?token=xxx
//   邮件链接点击进入的落地页 — 自动 deep link 回 App
// ============================================================
magicRoutes.get('/open', (req, res) => {
  const token = String(req.query.token || '');
  if (!token) return res.status(400).send('Missing token');

  const deepLink = `${APP_URL_SCHEME}://magic?token=${encodeURIComponent(token)}`;

  const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>${APP_NAME} 登录</title>
<style>
  body { margin:0; padding:0; font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif;
         background: linear-gradient(135deg, #FF7878, #E63946); min-height: 100vh;
         display: flex; align-items: center; justify-content: center; color: white; text-align: center; }
  .card { background: rgba(255,255,255,0.15); padding: 32px; border-radius: 20px; max-width: 360px; }
  .emoji { font-size: 48px; margin-bottom: 12px; }
  h1 { margin: 0 0 8px; font-size: 22px; }
  p  { opacity: 0.9; line-height: 1.6; font-size: 14px; }
  a  { display:inline-block; background: white; color:#E63946; padding:12px 28px;
       border-radius: 12px; text-decoration:none; font-weight:600; margin-top: 16px; }
</style>
</head>
<body>
  <div class="card">
    <div class="emoji">🎉</div>
    <h1>正在打开 ${APP_NAME}...</h1>
    <p>如果未自动跳转,请手动打开 App,<br/>或在 App 中输入邮件中的 6 位验证码。</p>
    <a href="${deepLink}">手动打开 App</a>
  </div>
  <script>
    // 自动尝试 deep link
    setTimeout(function(){ window.location.href = ${JSON.stringify(deepLink)}; }, 50);
  </script>
</body></html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
});
