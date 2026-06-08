// GET /account     — return current user
// DELETE /account  — delete account & all data(隐私法规要求)
import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';
import { HttpError } from '../middleware/error.js';

export const accountRoutes = Router();
accountRoutes.use(requireAuth);

accountRoutes.get('/', async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.sub },
      include: {
        _count: {
          select: { ledgerBooks: true, contacts: true, transactions: true, reminders: true },
        },
      },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    // 防止 CDN/浏览器缓存含敏感信息的 profile
    res.setHeader('Cache-Control', 'no-store');
    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      created_at: user.createdAt.toISOString(),
      stats: user._count,
    });
  } catch (err) { next(err); }
});

accountRoutes.delete('/', async (req, res, next) => {
  try {
    const userId = req.user!.sub;
    // 先取 email,MagicToken.email 没有 FK 必须显式清理
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) return res.status(404).json({ error: 'User not found' });

    // 事务包裹(callback 形式,可获取中间结果)
    // 否则删除账户后,旧 token 仍可用于"用同一 email 创建新账户" → 隐私泄露
    const result = await prisma.$transaction(async (tx) => {
      const deletedTokens = await tx.magicToken.deleteMany({
        where: { email: user.email },
      });
      // 注:已删除的用户记录 user 也一并清理,避免审计时看到已注销用户
      await tx.user.delete({ where: { id: userId } });
      return { deletedTokens: deletedTokens.count };
    });

    // 不打印 email,只记录数量(避免审计日志泄露 PII)
    console.log('[Account] deleted user', userId, 'cleared magic tokens:', result.deletedTokens);
    res.json({ ok: true });
  } catch (err) { next(err); }
});
