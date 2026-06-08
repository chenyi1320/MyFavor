import { PrismaClient } from '@prisma/client';

// === 防止 dev 热重载时连接池耗尽 ===
// tsx watch / nodemon 每次重启会 new PrismaClient,但旧实例没有 disconnect()
// 把单例挂到 globalThis,确保整个进程只用一个 client
const g = globalThis as unknown as { prisma?: PrismaClient };

export const prisma =
  g.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') {
  g.prisma = prisma;
}

// 进程退出时优雅关闭
process.on('beforeExit', async () => {
  await prisma.$disconnect();
});
