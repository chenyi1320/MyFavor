// GET /account     — return current user
// DELETE /account  — delete account & all data(Apple requires this)
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
    // Cascading delete via Prisma onDelete: Cascade
    await prisma.user.delete({ where: { id: userId } });
    res.json({ ok: true });
  } catch (err) { next(err); }
});
