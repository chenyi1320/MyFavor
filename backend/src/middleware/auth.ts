import type { Request, Response, NextFunction } from 'express';
import { verifyJWT, type JWTPayload } from '../lib/jwt.js';

declare global {
  namespace Express {
    interface Request {
      user?: JWTPayload;
    }
  }
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }
  try {
    const token = header.substring('Bearer '.length);
    const payload = verifyJWT(token);
    // 强制校验 sub 存在(避免后续 req.user!.sub 拿到 undefined)
    if (!payload?.sub || typeof payload.sub !== 'string') {
      return res.status(401).json({ error: 'Invalid token payload' });
    }
    req.user = payload;
    next();
  } catch (err) {
    // 不打印 err.message(可能含 token 片段),只记录布尔状态
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}
