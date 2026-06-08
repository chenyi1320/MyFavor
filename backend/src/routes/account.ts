// GET /account     — return current user
// DELETE /account  — delete account & all data(隐私法规要求)
import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';

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

    // 事务包裹:Cascade + 清理 MagicToken
    // 否则删除账户后,旧 token 仍可用于"用同一 email 创建新账户" → 隐私泄露
    await prisma.$transaction([
      prisma.magicToken.deleteMany({ where: { email: user.email } }),
      prisma.user.delete({ where: { id: userId } }),
    ]);

    res.json({ ok: true });
  } catch (err) { next(err); }
});
