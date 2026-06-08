// MyFavor — Resend email integration
import { Resend } from 'resend';

// === 强制:启动时校验 Resend API Key ===
// 缺失直接 throw,服务起不来 → 强制运维修配置
const apiKey = process.env.RESEND_API_KEY;
if (!apiKey) {
  throw new Error(
    '[FATAL] RESEND_API_KEY required.\n' +
    '在 https://resend.com/api-keys 创建一个,然后在 .env 中设置 RESEND_API_KEY=<你的 key>'
  );
}

export const resend = new Resend(apiKey);
export const FROM = process.env.RESEND_FROM_EMAIL || 'MyFavor <onboarding@resend.dev>';
export const APP_NAME = process.env.APP_NAME || 'MyFavor';
export const APP_URL = process.env.APP_URL || 'http://localhost:3000';
export const APP_URL_SCHEME = process.env.APP_URL_SCHEME || 'myfavor';

/**
 * 发送 Magic Link 登录邮件
 * 邮件同时包含:
 *  1) 可点击的链接(自动登录)
 *  2) 6 位验证码(在 App 中手动输入)
 */
export async function sendMagicLinkEmail(opts: {
  to: string;
  token: string;
  code: string;
}): Promise<{ id: string }> {
  const { to, token, code } = opts;

  // 链接 -- 先指向 Web 落地页,落地页再 deep link 到 App
  const link = `${APP_URL}/auth/magic/open?token=${encodeURIComponent(token)}`;

  const html = renderMagicLinkHTML({ code, link });
  const text = renderMagicLinkText({ code, link });

  const { data, error } = await resend.emails.send({
    from: FROM,
    to,
    subject: `${APP_NAME} 登录验证 - ${code}`,
    html,
    text,
    // 移除 X-Entity-Ref-ID 头(之前含 token 前 8 位,会泄露到 Resend 后台)
  });

  if (error) {
    console.error('[Email] Resend error:', error);

    // 把 Resend 的英文错误翻译成可读的中文 + 修复建议
    const raw = String(error.message || error.name || '');
    const low = raw.toLowerCase();
    let friendly = '邮件发送失败';
    let hint = '请稍后重试';

    if (low.includes('only send testing emails to your own email')) {
      friendly = 'Resend 免费版限制: 验证码只能发到注册 Resend 时使用的那个邮箱';
      hint = '方案 A:去 https://resend.com/audiences 添加并验证新邮箱;方案 B:在 Resend 升级到付费版;方案 C:用自己域名配 RESEND_FROM_EMAIL 后即可发任意邮箱';
    } else if (low.includes('invalid api key') || low.includes('unauthorized') || low.includes('forbidden')) {
      friendly = 'Resend API Key 无效或权限不足';
      hint = '检查 .env 里的 RESEND_API_KEY(在 https://resend.com/api-keys 重新生成)';
    } else if (low.includes('domain not verified') || low.includes('not a valid domain') || low.includes('from address')) {
      friendly = '发件人域名未通过 Resend 验证';
      hint = '在 Resend 添加并验证发件域名,或临时改用默认 onboarding@resend.dev';
    } else if (low.includes('rate limit') || low.includes('too many requests') || low.includes('429')) {
      friendly = 'Resend 发送频率超限';
      hint = '请等待几分钟后重试';
    } else if (low.includes('recipient') || low.includes('invalid email')) {
      friendly = '收件邮箱被 Resend 拒绝';
      hint = '请换一个合法邮箱地址';
    }

    const e = new Error(`${friendly} | 提示:${hint}`) as Error & { code?: string; httpStatus?: number };
    e.code = 'EMAIL_SEND_FAILED';
    e.httpStatus = 502;  // Bad Gateway — 上游邮件服务异常
    throw e;
  }
  return { id: data?.id || '' };
}

// ============================================================
// HTML 模板 -- 墨绿 + 琥珀 配色,移动端友好
// ============================================================
function renderMagicLinkHTML(opts: { code: string; link: string }): string {
  const { code, link } = opts;
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${APP_NAME} · 登录验证码</title>
</head>
<body style="margin:0;padding:0;background:#FAF8F4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','PingFang SC','Hiragino Sans GB',sans-serif;color:#2C3E2D;">
  <div style="max-width:480px;margin:32px auto;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #E8E4DC;">

    <!-- header: 墨绿顶栏 -->
    <div style="background:#2C5F4F;padding:28px 24px;text-align:center;">
      <div style="color:#F5E6D3;font-size:20px;font-weight:600;letter-spacing:2px;">${APP_NAME}</div>
      <div style="color:rgba(245,230,211,0.75);font-size:12px;margin-top:8px;letter-spacing:1px;">自托管 · 你的数据你做主</div>
    </div>

    <!-- body -->
    <div style="padding:32px 28px;">
      <h2 style="margin:0 0 12px;font-size:17px;color:#2C3E2D;font-weight:600;">这是你的登录验证码</h2>
      <p style="margin:0 0 24px;font-size:14px;color:#6B7B6C;line-height:1.7;">
        你正在登录 ${APP_NAME}。验证码 <strong>15 分钟</strong>内有效,
        请勿向他人透露。
      </p>

      <!-- 验证码卡片 -->
      <div style="background:#F5E6D3;border-radius:12px;padding:24px 16px;text-align:center;margin-bottom:20px;">
        <div style="font-size:11px;color:#8B7355;letter-spacing:3px;margin-bottom:12px;">VERIFICATION CODE</div>
        <div style="font-size:32px;font-weight:700;letter-spacing:10px;color:#2C3E2D;font-family:'SF Mono','Menlo',monospace;">
          ${code}
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
        <a href="${link}" style="display:inline-block;background:#2C5F4F;color:#F5E6D3;padding:13px 30px;border-radius:10px;text-decoration:none;font-weight:500;font-size:14px;letter-spacing:1px;">
          一键登录
        </a>
      </div>

      <p style="margin:28px 0 0;font-size:12px;color:#8E8E93;line-height:1.6;">
        如果你没有发起这次请求,请忽略本邮件,你的账户不会受到任何影响。
      </p>
    </div>

    <div style="background:#FAF8F4;padding:14px 28px;text-align:center;font-size:11px;color:#A0A0A0;border-top:1px solid #E8E4DC;">
      © ${new Date().getFullYear()} ${APP_NAME} · 此邮件由系统自动发送,请勿回复
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
