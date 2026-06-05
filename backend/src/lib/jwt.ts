import jwt from 'jsonwebtoken';

const SECRET = process.env.JWT_SECRET || 'dev_secret_change_me';
const EXPIRES_IN = process.env.JWT_EXPIRES_IN || '30d';

export interface JWTPayload {
  sub: string;     // user id
}

export function signJWT(payload: JWTPayload): { token: string; expiresAt: Date } {
  const token = jwt.sign(payload, SECRET, { expiresIn: EXPIRES_IN } as jwt.SignOptions);
  const decoded = jwt.decode(token) as { exp?: number } | null;
  const expiresAt = decoded?.exp ? new Date(decoded.exp * 1000) : new Date(Date.now() + 30 * 24 * 3600 * 1000);
  return { token, expiresAt };
}

export function verifyJWT(token: string): JWTPayload {
  return jwt.verify(token, SECRET) as JWTPayload;
}

