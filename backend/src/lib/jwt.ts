import jwt, { type SignOptions } from 'jsonwebtoken';

// === 强制:启动时校验 JWT_SECRET ===
// 任何弱密钥/默认值都会直接 throw,服务起不来 → 强制运维修配置
function getSecret(): string {
  const s = process.env.JWT_SECRET;
  if (!s || s.length < 32) {
    throw new Error(
      '[FATAL] JWT_SECRET missing or too weak (min 32 chars).\n' +
      '生成强密钥: openssl rand -hex 64\n' +
      '然后在 .env 中设置 JWT_SECRET=<你的密钥>'
    );
  }
  return s;
}
const SECRET = getSecret();

// === 解析 JWT_EXPIRES_IN 为毫秒(同时供 token 签名和返回给客户端) ===
// 避免 EXPIRES_IN 与 EXPIRES_MS 不一致导致客户端误判有效期
const EXPIRES_IN = process.env.JWT_EXPIRES_IN || '30d';
function parseExpiryToMs(s: string): number {
  const m = s.match(/^(\d+)([smhd])$/);
  if (!m) return 30 * 24 * 3600 * 1000; // fallback 30 天
  const n = parseInt(m[1], 10);
  return n * { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[m[2] as 's'|'m'|'h'|'d'];
}
const EXPIRES_MS = parseExpiryToMs(EXPIRES_IN);

export interface JWTPayload {
  sub: string;     // user id
}

export function signJWT(payload: JWTPayload): { token: string; expiresAt: Date } {
  const token = jwt.sign(payload, SECRET, { expiresIn: EXPIRES_IN } as SignOptions);
  // 与签名共用同一个 EXPIRES_MS,确保 token 实际过期与返回给客户端的一致
  const expiresAt = new Date(Date.now() + EXPIRES_MS);
  return { token, expiresAt };
}

export function verifyJWT(token: string): JWTPayload {
  return jwt.verify(token, SECRET) as JWTPayload;
}

