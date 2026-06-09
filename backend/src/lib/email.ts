// MyFavor — 邮件服务
// 支持两种发送模式(由环境变量决定,运行时切换):
//   1) SMTP 模式(优先):配置 SMTP_HOST 即启用,适配 Gmail / 阿里云 DirectMail / 163 / QQ / Mailpit / 任何标准 SMTP
//   2) Resend 模式(回退):未配 SMTP_HOST 时使用,需 RESEND_API_KEY
//
// 选择规则(在模块加载时确定一次):
//   SMTP_HOST 已设 → SMTP 模式(无视 RESEND_API_KEY 是否存在)
//   SMTP_HOST 未设 → Resend 模式(必须 RESEND_API_KEY,否则启动失败)

import { Resend } from 'resend';
import nodemailer, { type Transporter } from 'nodemailer';

// ============================================================
// 模式判定 & 共享配置
// ============================================================
export const APP_NAME = process.env.APP_NAME || 'MyFavor';
export const APP_URL = process.env.APP_URL || 'http://localhost:3000';
export const APP_URL_SCHEME = process.env.APP_URL_SCHEME || 'myfavor';

export type EmailMode = 'smtp' | 'resend';

export const EMAIL_MODE: EmailMode = process.env.SMTP_HOST ? 'smtp' : 'resend';

// ============================================================
// SMTP 模式(nodemailer)
// ============================================================
let smtpTransporter: Transporter | null = null;
if (EMAIL_MODE === 'smtp') {
  const host = process.env.SMTP_HOST!;
  const port = Number(process.env.SMTP_PORT || 465);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (!user || !pass) {
    throw new Error(
      '[FATAL] SMTP 模式要求 SMTP_USER 和 SMTP_PASS 同时设置。\n' +
      '示例(Gmail):SMTP_USER=you@gmail.com, SMTP_PASS=<16 位 App Password>'
    );
  }

  // secure:465 用 SSL,true;587 用 STARTTLS,false
  const secure = port === 465;

  smtpTransporter = nodemailer.createTransport({
    host,
    port,
    secure,
    auth: { user, pass },
    // 大部分服务对自签证书友好,这里不开 strict
    tls: { rejectUnauthorized: false },
    // 防止挂死
    connectionTimeout: 10_000,
    socketTimeout: 10_000,
  });

  console.log(`[Email] SMTP 模式: ${user} via ${host}:${port} (secure=${secure})`);
}

// ============================================================
// Resend 模式
// ============================================================
let resend: Resend | null = null;
let resendFrom = '';
if (EMAIL_MODE === 'resend') {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    throw new Error(
      '[FATAL] Resend 模式要求 RESEND_API_KEY(且 SMTP_HOST 未设置)。\n' +
      '在 https://resend.com/api-keys 创建,或在 .env 中设置 SMTP_HOST 切到 SMTP 模式。'
    );
  }
  resend = new Resend(apiKey);
  resendFrom = process.env.RESEND_FROM_EMAIL || 'MyFavor <onboarding@resend.dev>';
  console.log(`[Email] Resend 模式: from=${resendFrom}`);
}

// ============================================================
// From 地址(SMTP 模式用)
// ============================================================
// SMTP_FROM 优先,未设则用 SMTP_USER
export const SMTP_FROM: string =
  process.env.SMTP_FROM || (process.env.SMTP_USER ? `"${APP_NAME}" <${process.env.SMTP_USER}>` : '');

// === HTML 转义工具(防止 APP_NAME 等环境变量中含 < > & " ' 时被解释为 HTML) ===
function escHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!)
  );
}

/**
 * 发送 Magic Link 登录邮件
 * 同时包含:
 *  1) 可点击的链接(自动登录)
 *  2) 6 位验证码(在 App 中手动输入)
 */
export async function sendMagicLinkEmail(opts: SendMagicLinkOptions): Promise<{ id: string }> {
  const { to, token, code } = opts;

  // 链接:Web 落地页再 deep link 到 App
  const link = `${APP_URL}/auth/magic/open?token=${encodeURIComponent(token)}`;

  const html = renderMagicLinkHTML({ code, link });
  const text = renderMagicLinkText({ code, link });
  const subject = `${APP_NAME} 登录验证 - ${code}`;

  if (EMAIL_MODE === 'smtp') {
    return sendViaSMTP({ to, subject, html, text });
  }
  return sendViaResend({ to, subject, html, text });
}

// ============================================================
// 公开类型 & 发送实现
// ============================================================
export interface SendMagicLinkOptions {
  to: string;
  token: string;
  code: string;
}

// ----- SMTP 发送 -----
async function sendViaSMTP(opts: {
  to: string;
  subject: string;
  html: string;
  text: string;
}): Promise<{ id: string }> {
  if (!smtpTransporter) {
    throw new Error('[Email] SMTP transporter 未初始化');
  }
  if (!SMTP_FROM) {
    throw new Error('[Email] SMTP_FROM / SMTP_USER 未设置');
  }

  try {
    const info = await smtpTransporter.sendMail({
      from: SMTP_FROM,
      to: opts.to,
      subject: opts.subject,
      html: opts.html,
      text: opts.text,
    });
    return { id: info.messageId };
  } catch (err: any) {
    throw translateSMTPError(err);
  }
}

// ----- Resend 发送 -----
async function sendViaResend(opts: {
  to: string;
  subject: string;
  html: string;
  text: string;
}): Promise<{ id: string }> {
  if (!resend) {
    throw new Error('[Email] Resend client 未初始化');
  }

  // 邮件发送加超时(避免 Resend 卡死时长时间挂起 Express handler)
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const { data, error } = await resend.emails.send(
      {
        from: resendFrom,
        to: opts.to,
        subject: opts.subject,
        html: opts.html,
        text: opts.text,
        // 移除 X-Entity-Ref-ID 头(之前含 token 前 8 位,会泄露到 Resend 后台)
      },
      { signal: controller.signal } as any
    );
    if (error) {
      throw translateResendError(error);
    }
    return { id: data?.id || '' };
  } finally {
    clearTimeout(timer);
  }
}

// ============================================================
// 错误翻译
// ============================================================
type EmailError = Error & { code?: string; httpStatus?: number };

function translateSMTPError(error: any): EmailError {
  // 只打脱敏后的错误类别,不打印 message(可能含请求体/邮箱)
  console.error('[Email] SMTP error code:', error?.code ?? error?.responseCode ?? 'unknown');

  const raw = String(error.message || error.name || '');
  const low = raw.toLowerCase();
  let friendly = '邮件发送失败';
  let hint = '请稍后重试';

  if (
    low.includes('eauth') ||
    low.includes('invalid login') ||
    low.includes('username and password not accepted') ||
    low.includes('535')
  ) {
    friendly = 'SMTP 认证失败';
    hint = '检查 SMTP_USER / SMTP_PASS(Gmail 用 App Password,不是登录密码)';
  } else if (low.includes('econnrefused') || low.includes('etimedout') || low.includes('enotfound')) {
    friendly = 'SMTP 服务器连接失败';
    hint = '检查 SMTP_HOST / SMTP_PORT,确认网络可达、防火墙开放';
  } else if (low.includes('self-signed certificate') || low.includes('cert')) {
    friendly = 'SMTP TLS 证书错误';
    hint = '检查证书有效性,或临时将 tls.rejectUnauthorized 设为 false';
  } else if (low.includes('recipient') || low.includes('mailbox') || low.includes('user unknown')) {
    friendly = '收件邮箱被 SMTP 服务商拒绝';
    hint = '请换一个合法邮箱地址';
  } else if (
    low.includes('rate limit') ||
    low.includes('too many') ||
    low.includes('421') ||
    low.includes('452')
  ) {
    friendly = 'SMTP 发送频率超限';
    hint = 'Gmail 个人账号每日上限 ~500 封,阿里云看配额';
  }

  const e = new Error(`${friendly} | 提示:${hint}`) as EmailError;
  e.code = 'EMAIL_SEND_FAILED';
  e.httpStatus = 502;
  return e;
}

function translateResendError(error: any): EmailError {
  // 只打脱敏后的错误类别,不打印 message(可能含请求体/邮箱)
  console.error('[Email] Resend error code:', error?.statusCode ?? 'unknown');

  const raw = String(error.message || error.name || '');
  const low = raw.toLowerCase();
  let friendly = '邮件发送失败';
  let hint = '请稍后重试';

  if (low.includes('only send testing emails to your own email')) {
    friendly = 'Resend 免费版限制: 验证码只能发到注册 Resend 时使用的那个邮箱';
    hint = '方案 A:去 https://resend.com/audiences 添加并验证新邮箱;方案 B:在 Resend 升级到付费版;方案 C:用自己域名配 RESEND_FROM_EMAIL 后即可发任意邮箱;方案 D:改用 SMTP 模式';
  } else if (low.includes('invalid api key') || low.includes('unauthorized') || low.includes('forbidden')) {
    friendly = 'Resend API Key 无效或权限不足';
    hint = '检查 .env 里的 RESEND_API_KEY(在 https://resend.com/api-keys 重新生成)';
  } else if (low.includes('domain not verified') || low.includes('not a valid domain') || low.includes('from address')) {
    friendly = '发件人域名未通过 Resend 验证';
    hint = '在 Resend 添加并验证发件域名,或临时改用默认 onboarding@resend.dev,或改用 SMTP 模式';
  } else if (low.includes('rate limit') || low.includes('too many requests') || low.includes('429')) {
    friendly = 'Resend 发送频率超限';
    hint = '请等待几分钟后重试';
  } else if (low.includes('recipient') || low.includes('invalid email')) {
    friendly = '收件邮箱被 Resend 拒绝';
    hint = '请换一个合法邮箱地址';
  }

  const e = new Error(`${friendly} | 提示:${hint}`) as EmailError;
  e.code = 'EMAIL_SEND_FAILED';
  e.httpStatus = 502;  // Bad Gateway — 上游邮件服务异常
  return e;
}

// ============================================================
// HTML 模板 -- 墨绿 + 琥珀 配色,移动端友好
// ============================================================
function renderMagicLinkHTML(opts: { code: string; link: string }): string {
  const { code, link } = opts;
  // 所有可能含特殊字符的变量都过 escHtml
  const safeApp = escHtml(APP_NAME);
  const safeCode = escHtml(code);
  const safeLink = escHtml(link);
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${safeApp} · 登录验证码</title>
</head>
<body style="margin:0;padding:0;background:#FAF8F4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','PingFang SC','Hiragino Sans GB',sans-serif;color:#2C3E2D;">
  <div style="max-width:480px;margin:32px auto;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #E8E4DC;">

    <!-- header: 墨绿顶栏 -->
    <div style="background:#2C5F4F;padding:28px 24px;text-align:center;">
      <div style="color:#F5E6D3;font-size:20px;font-weight:600;letter-spacing:2px;">${safeApp}</div>
      <div style="color:rgba(245,230,211,0.75);font-size:12px;margin-top:8px;letter-spacing:1px;">自托管 · 你的数据你做主</div>
    </div>

    <!-- body -->
    <div style="padding:32px 28px;">
      <h2 style="margin:0 0 12px;font-size:17px;color:#2C3E2D;font-weight:600;">这是你的登录验证码</h2>
      <p style="margin:0 0 24px;font-size:14px;color:#6B7B6C;line-height:1.7;">
        你正在登录 ${safeApp}。验证码 <strong>15 分钟</strong>内有效,
        请勿向他人透露。
      </p>

      <!-- 验证码卡片 -->
      <div style="background:#F5E6D3;border-radius:12px;padding:24px 16px;text-align:center;margin-bottom:20px;">
        <div style="font-size:11px;color:#8B7355;letter-spacing:3px;margin-bottom:12px;">VERIFICATION CODE</div>
        <div style="font-size:32px;font-weight:700;letter-spacing:10px;color:#2C3E2D;font-family:'SF Mono','Menlo',monospace;">
          ${safeCode}
        </div>
      </div>

      <!-- 分隔 -->
      <div style="display:flex;align-items:center;margin:24px 0;">
        <div style="flex:1;height:1px;background:#E8E4DC;"></div>
        <div style="padding:0 12px;font-size:11px;color:#A0A0A0;letter-spacing:1px;">或</div>
        <div style="flex:1;height:1px;background:#E8E4DC;"></div>
      </div>

      <!-- 一键登录 -->
      <div style="text-align:center;">
        <a href="${safeLink}" style="display:inline-block;background:#2C5F4F;color:#F5E6D3;padding:13px 30px;border-radius:10px;text-decoration:none;font-weight:500;font-size:14px;letter-spacing:1px;">
          一键登录
        </a>
      </div>

      <p style="margin:28px 0 0;font-size:12px;color:#8E8E93;line-height:1.6;">
        如果你没有发起这次请求,请忽略本邮件,你的账户不会受到任何影响。
      </p>
    </div>

    <div style="background:#FAF8F4;padding:14px 28px;text-align:center;font-size:11px;color:#A0A0A0;border-top:1px solid #E8E4DC;">
      © ${new Date().getFullYear()} ${safeApp} · 此邮件由系统自动发送,请勿回复
    </div>
  </div>
</body>
</html>`;
}

function renderMagicLinkText(opts: { code: string; link: string }): string {
  return `${APP_NAME} 登录验证

验证码:${opts.code}

或点击链接登录:${opts.link}

15 分钟内有效。如非本人操作请忽略。`;
}
