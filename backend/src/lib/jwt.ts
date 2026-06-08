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

const EXPIRES_IN = process.env.JWT_EXPIRES_IN || '30d';
const EXPIRES_MS = 30 * 24 * 3600 * 1000; // fallback 30 天

export interface JWTPayload {
  sub: string;     // user id
}

export function signJWT(payload: JWTPayload): { token: string; expiresAt: Date } {
  const token = jwt.sign(payload, SECRET, { expiresIn: EXPIRES_IN } as SignOptions);
  // 直接计算过期时间(避免依赖 jwt.decode 的 fallback)
  const expiresAt = new Date(Date.now() + EXPIRES_MS);
  return { token, expiresAt };
}

export function verifyJWT(token: string): JWTPayload {
  return jwt.verify(token, SECRET) as JWTPayload;
}

