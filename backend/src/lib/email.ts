// MyFavor — Resend email integration
import { Resend } from 'resend';

const apiKey = process.env.RESEND_API_KEY;
if (!apiKey) {
  console.warn('[Email] RESEND_API_KEY not set, emails will fail');
}

export const resend = new Resend(apiKey || 'missing');
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
    headers: {
      'X-Entity-Ref-ID': token.slice(0, 8),
    },
  });

  if (error) {
    console.error('[Email] Resend error:', error);
    throw new Error(`Failed to send email: ${error.message}`);
  }
  return { id: data?.id || '' };
}

// ============================================================
// HTML 模板 -- 简洁、品牌色,移动端友好
// ============================================================
function renderMagicLinkHTML(opts: { code: string; link: string }): string {
  const { code, link } = opts;
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${APP_NAME} 登录</title>
</head>
<body style="margin:0;padding:0;background:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','PingFang SC','Hiragino Sans GB',sans-serif;color:#1c1c1e;">
  <div style="max-width:480px;margin:32px auto;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 4px 20px rgba(255,107,107,0.08);">

    <!-- header -->
    <div style="background:linear-gradient(135deg,#FF7878,#E63946);padding:32px 24px;text-align:center;">
      <div style="font-size:42px;line-height:1;margin-bottom:8px;">📖</div>
      <div style="color:#fff;font-size:22px;font-weight:700;letter-spacing:1px;">${APP_NAME}</div>
      <div style="color:rgba(255,255,255,0.85);font-size:13px;margin-top:6px;">人情往来,温情有数</div>
    </div>

    <!-- body -->
    <div style="padding:32px 28px;">
      <h2 style="margin:0 0 12px;font-size:18px;color:#1c1c1e;">您正在登录 ${APP_NAME}</h2>
      <p style="margin:0 0 24px;font-size:14px;color:#6e6e73;line-height:1.6;">
        为确保是您本人操作,请在 15 分钟内完成以下任一方式登录。
      </p>

      <!-- 方式 1:6 位验证码 -->
      <div style="background:#FFF5F5;border-radius:14px;padding:20px;text-align:center;margin-bottom:20px;">
        <div style="font-size:12px;color:#8e8e93;margin-bottom:8px;">在 App 中输入此验证码</div>
        <div style="font-size:36px;font-weight:700;letter-spacing:12px;color:#E63946;font-family:'SF Mono',Menlo,monospace;">
          ${code}
        </div>
      </div>

      <!-- 分隔 -->
      <div style="display:flex;align-items:center;margin:24px 0;">
        <div style="flex:1;height:1px;background:#e5e5ea;"></div>
        <div style="padding:0 12px;font-size:12px;color:#8e8e93;">或</div>
        <div style="flex:1;height:1px;background:#e5e5ea;"></div>
      </div>

      <!-- 方式 2:一键链接 -->
      <div style="text-align:center;">
        <a href="${link}" style="display:inline-block;background:linear-gradient(135deg,#FF7878,#E63946);color:#ffffff;padding:14px 32px;border-radius:12px;text-decoration:none;font-weight:600;font-size:15px;">
          点此一键登录
        </a>
      </div>

      <p style="margin:32px 0 0;font-size:12px;color:#8e8e93;line-height:1.6;">
        如果您没有请求登录 ${APP_NAME},请直接忽略本邮件。<br/>
        此验证码 15 分钟后失效,且只能使用一次。
      </p>
    </div>

    <div style="background:#f5f5f7;padding:16px 28px;text-align:center;font-size:11px;color:#8e8e93;">
      © ${new Date().getFullYear()} ${APP_NAME}. 此邮件由系统自动发送,请勿回复。
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
