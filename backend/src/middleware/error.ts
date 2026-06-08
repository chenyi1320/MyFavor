import type { Request, Response, NextFunction } from 'express';

/**
 * 业务主动抛的 HttpError,可以被安全地暴露给客户端
 */
export class HttpError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public expose = true,
    public code?: string,
  ) {
    super(message);
    this.name = 'HttpError';
  }
}

// Prisma 已知错误码 → 业务文案映射(不暴露 SQL/字段细节)
const PRISMA_ERROR_MESSAGES: Record<string, string> = {
  P2002: '数据已存在,请勿重复提交',
  P2025: '记录不存在或已被删除',
  P2003: '关联数据不存在',
  P2010: '请求参数不合法',
};

export function errorHandler(
  err: any,
  _req: Request,
  res: Response,
  _next: NextFunction
) {
  // === 服务端日志:结构化记录,避免敏感数据泄露到日志系统 ===
  // (不直接 log 整个 err 对象,Prisma 错误可能含 SQL 片段、字段名)
  console.error('[ERROR]', {
    name: err?.name,
    code: err?.code,
    message: err?.message,
    stack: process.env.NODE_ENV === 'development' ? err?.stack : undefined,
  });

  const status = err.statusCode || err.status || 500;

  // 1. 业务主动抛的 HttpError → 安全暴露 message
  if (err instanceof HttpError) {
    return res.status(err.statusCode).json({
      error: err.expose ? err.message : 'Internal Server Error',
      ...(err.expose && err.code ? { code: err.code } : {}),
    });
  }

  // 2. Prisma 已知错误 → 映射为业务文案(不暴露 SQL)
  if (err?.code && PRISMA_ERROR_MESSAGES[err.code]) {
    return res.status(status === 500 ? 400 : status).json({
      error: PRISMA_ERROR_MESSAGES[err.code],
    });
  }

  // 3. 未知错误 → 统一回 500,不暴露内部信息
  res.status(500).json({ error: 'Internal Server Error' });
}
