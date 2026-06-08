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

// === 安全:启动时强制要求 JWT_SECRET(必须在路由加载前导入) ===
import './lib/jwt.js';  // 触发 jwt.ts 顶部的启动校验

const ALLOWED_ORIGINS = (process.env.CORS_ORIGINS || 'http://localhost:3000,http://localhost:5173')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, cb) => {
    // 同源 / curl / Postman 无 origin 头,放行
    if (!origin) return cb(null, true);
    if (ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    return cb(new Error(`CORS blocked: ${origin}`));
  },
  exposedHeaders: ['x-server-time'],
  credentials: true,
}));
app.set('trust proxy', parseInt(process.env.TRUST_PROXY_COUNT || '1', 10));
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
  // 只输出布尔状态,不打印邮箱/URL 实际值(避免泄露内部域名、账号)
  console.log(`   Resend:     ${process.env.RESEND_API_KEY ? '✅ configured' : '❌ MISSING'}`);
  console.log(`   From email: ${process.env.RESEND_FROM_EMAIL ? '✅ configured' : '⚠️  using default'}`);
  console.log(`   App URL:    ${process.env.APP_URL ? '✅ configured' : '⚠️  using default'}`);
  console.log(`   Database:   ${process.env.DATABASE_URL ? '✅ configured' : '❌ MISSING'}`);
});


