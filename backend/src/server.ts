// MyFavor backend entry — Express + Prisma + Magic Link (邮箱) + JWT
import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { magicRoutes } from './routes/magic.js';
import { syncRoutes } from './routes/sync.js';
import { accountRoutes } from './routes/account.js';
import { errorHandler } from './middleware/error.js';

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

app.use(cors({
  origin: '*',                  // 生产请收紧
  exposedHeaders: ['x-server-time'],
}));
app.use(express.json({ limit: '5mb' }));

// Health check
app.get('/', (_req, res) => res.json({ ok: true, service: 'MyFavor API', time: new Date().toISOString() }));
app.get('/health', (_req, res) => res.json({ status: 'healthy' }));

// Routes
app.use('/auth/magic', magicRoutes);   // Magic Link 邮箱登录
app.use('/sync', syncRoutes);
app.use('/account', accountRoutes);

// Error handler
app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`🚀 MyFavor API listening on http://localhost:${PORT}`);
  console.log(`   Resend:     ${process.env.RESEND_API_KEY ? '✅ configured' : '❌ MISSING'}`);
  console.log(`   From email: ${process.env.RESEND_FROM_EMAIL}`);
  console.log(`   App URL:    ${process.env.APP_URL}`);
  console.log(`   Database:   ${process.env.DATABASE_URL?.replace(/:[^:]+@/, ':***@')}`);
});


