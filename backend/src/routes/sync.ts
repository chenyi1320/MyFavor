// POST /sync/push  +  GET /sync/pull?since=ISO_DATE
import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';

export const syncRoutes = Router();
syncRoutes.use(requireAuth);

// 单次同步的最大记录数(防 DoS / 超大请求)
const MAX_ITEMS_PER_PUSH = 500;
const MAX_ITEMS_PER_PULL = 1000;

// ===== helpers =====
function snakeToCamel(obj: any): any {
  if (Array.isArray(obj)) return obj.map(snakeToCamel);
  if (obj && typeof obj === 'object') {
    const out: any = {};
    for (const [k, v] of Object.entries(obj)) {
      const ck = k.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
      out[ck] = snakeToCamel(v);
    }
    return out;
  }
  return obj;
}

function dtoFromBook(b: any) {
  return {
    userId: b.userId,                  // 透传给 iOS,用于本地 userId 字段
    clientId: b.clientId,
    serverId: b.id,
    title: b.title,
    categoryRaw: b.categoryRaw,
    directionRaw: b.directionRaw,
    eventDate: b.eventDate.toISOString(),
    note: b.note,
    coverColorHex: b.coverColorHex,
    isClosed: b.isClosed,
    updatedAt: b.updatedAt.toISOString(),
    deletedAt: b.deletedAt?.toISOString() ?? null,
  };
}
function dtoFromContact(c: any) {
  return {
    userId: c.userId,                  // 透传给 iOS
    clientId: c.clientId,
    serverId: c.id,
    name: c.name,
    pinyinInitial: c.pinyinInitial,
    phone: c.phone,
    relationshipRaw: c.relationshipRaw,
    avatarEmoji: c.avatarEmoji,
    note: c.note,
    birthday: c.birthday?.toISOString() ?? null,
    updatedAt: c.updatedAt.toISOString(),
    deletedAt: c.deletedAt?.toISOString() ?? null,
  };
}
function dtoFromTx(t: any) {
  return {
    userId: t.userId,                  // 透传给 iOS
    clientId: t.clientId,
    serverId: t.id,
    amount: t.amount.toString(),
    giftKindRaw: t.giftKindRaw,
    itemDescription: t.itemDescription,
    date: t.date.toISOString(),
    note: t.note,
    bookClientId: t.bookClientId,
    contactClientId: t.contactClientId,
    updatedAt: t.updatedAt.toISOString(),
    deletedAt: t.deletedAt?.toISOString() ?? null,
  };
}
function dtoFromReminder(r: any) {
  return {
    userId: r.userId,                  // 透传给 iOS
    clientId: r.clientId,
    serverId: r.id,
    title: r.title,
    date: r.date.toISOString(),
    useLunar: r.useLunar,
    advanceDays: r.advanceDays,
    note: r.note,
    colorHex: r.colorHex,
    isEnabled: r.isEnabled,
    updatedAt: r.updatedAt.toISOString(),
    deletedAt: r.deletedAt?.toISOString() ?? null,
  };
}

// ===== POST /sync/push =====
// Body: { ledger_books: [...], contacts: [...], transactions: [...], reminders: [...] }
// Resp: { ledger_books: [{client_id, server_id}], ... }
syncRoutes.post('/push', async (req, res, next) => {
  try {
    const userId = req.user!.sub;
    const body = snakeToCamel(req.body);
    const ledgerBooks  = (body.ledgerBooks  || []) as any[];
    const contacts     = (body.contacts     || []) as any[];
    const transactions = (body.transactions || []) as any[];
    const reminders    = (body.reminders    || []) as any[];

    // 数量限制(防 DoS / 巨大请求)
    const total = ledgerBooks.length + contacts.length + transactions.length + reminders.length;
    if (total > MAX_ITEMS_PER_PUSH) {
      return res.status(413).json({
        error: `单次推送数据过多,最多 ${MAX_ITEMS_PER_PUSH} 条`,
      });
    }

    // === 性能优化:一次性预加载所有 book/contact 的 clientId → serverId 映射 ===
    // 避免 transaction 处理时的 N+1 查询(原来每笔 tx 触发 2 次 findUnique)
    const bookClientIds = new Set<string>();
    const contactClientIds = new Set<string>();
    for (const t of transactions) {
      if (t.bookClientId) bookClientIds.add(t.bookClientId);
      if (t.contactClientId) contactClientIds.add(t.contactClientId);
    }
    for (const b of ledgerBooks) bookClientIds.add(b.clientId);
    for (const c of contacts) contactClientIds.add(c.clientId);

    const [existingBooks, existingContacts] = await Promise.all([
      bookClientIds.size > 0
        ? prisma.ledgerBook.findMany({
            where: { userId, clientId: { in: Array.from(bookClientIds) } },
            select: { id: true, clientId: true },
          })
        : Promise.resolve([] as { id: string; clientId: string }[]),
      contactClientIds.size > 0
        ? prisma.contact.findMany({
            where: { userId, clientId: { in: Array.from(contactClientIds) } },
            select: { id: true, clientId: true },
          })
        : Promise.resolve([] as { id: string; clientId: string }[]),
    ]);
    const bookIdMap = new Map(existingBooks.map((b) => [b.clientId, b.id]));
    const contactIdMap = new Map(existingContacts.map((c) => [c.clientId, c.id]));

    // === 整个 push 包在事务里:任一失败回滚 ===
    const result = await prisma.$transaction(async (tx) => {
      const bookMappings: { clientId: string; serverId: string }[] = [];
      for (const b of ledgerBooks) {
        const data = {
          title: b.title,
          categoryRaw: b.categoryRaw,
          directionRaw: b.directionRaw,
          eventDate: new Date(b.eventDate),
          note: b.note ?? '',
          coverColorHex: b.coverColorHex ?? '#2C5F4F',
          isClosed: !!b.isClosed,
          deletedAt: b.deletedAt ? new Date(b.deletedAt) : null,
        };
        const row = await tx.ledgerBook.upsert({
          where: { userId_clientId: { userId, clientId: b.clientId } },
          create: { ...data, userId, clientId: b.clientId },
          update: data,
        });
        bookMappings.push({ clientId: b.clientId, serverId: row.id });
        bookIdMap.set(b.clientId, row.id);
      }

      const contactMappings: { clientId: string; serverId: string }[] = [];
      for (const c of contacts) {
        const data = {
          name: c.name,
          pinyinInitial: c.pinyinInitial ?? '#',
          phone: c.phone ?? '',
          relationshipRaw: c.relationshipRaw ?? '朋友',
          avatarEmoji: c.avatarEmoji ?? '🙂',
          note: c.note ?? '',
          birthday: c.birthday ? new Date(c.birthday) : null,
          deletedAt: c.deletedAt ? new Date(c.deletedAt) : null,
        };
        const row = await tx.contact.upsert({
          where: { userId_clientId: { userId, clientId: c.clientId } },
          create: { ...data, userId, clientId: c.clientId },
          update: data,
        });
        contactMappings.push({ clientId: c.clientId, serverId: row.id });
        contactIdMap.set(c.clientId, row.id);
      }

      const txMappings: { clientId: string; serverId: string }[] = [];
      for (const t of transactions) {
        // 用本地 Map 查 bookId/contactId,0 次 DB 查询
        const bookId = t.bookClientId ? (bookIdMap.get(t.bookClientId) ?? null) : null;
        const contactId = t.contactClientId ? (contactIdMap.get(t.contactClientId) ?? null) : null;
        const data = {
          amount: t.amount,
          giftKindRaw: t.giftKindRaw ?? '礼金',
          itemDescription: t.itemDescription ?? '',
          date: new Date(t.date),
          note: t.note ?? '',
          bookClientId: t.bookClientId ?? null,
          bookId,
          contactClientId: t.contactClientId ?? null,
          contactId,
          deletedAt: t.deletedAt ? new Date(t.deletedAt) : null,
        };
        const row = await tx.transaction.upsert({
          where: { userId_clientId: { userId, clientId: t.clientId } },
          create: { ...data, userId, clientId: t.clientId },
          update: data,
        });
        txMappings.push({ clientId: t.clientId, serverId: row.id });
      }

      const reminderMappings: { clientId: string; serverId: string }[] = [];
      for (const r of reminders) {
        const data = {
          title: r.title,
          date: new Date(r.date),
          useLunar: !!r.useLunar,
          advanceDays: r.advanceDays ?? 7,
          note: r.note ?? '',
          colorHex: r.colorHex ?? '#2C5F4F',
          isEnabled: r.isEnabled !== false,
          deletedAt: r.deletedAt ? new Date(r.deletedAt) : null,
        };
        const row = await tx.reminder.upsert({
          where: { userId_clientId: { userId, clientId: r.clientId } },
          create: { ...data, userId, clientId: r.clientId },
          update: data,
        });
        reminderMappings.push({ clientId: r.clientId, serverId: row.id });
      }

      return { bookMappings, contactMappings, txMappings, reminderMappings };
    });

    res.json({
      ledger_books:  result.bookMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
      contacts:      result.contactMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
      transactions:  result.txMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
      reminders:     result.reminderMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
    });
  } catch (err) { next(err); }
});

// ===== GET /sync/pull?since=ISO_DATE =====
// Returns all rows where updatedAt > since(or all if since empty)
syncRoutes.get('/pull', async (req, res, next) => {
  try {
    const userId = req.user!.sub;
    const since = req.query.since as string | undefined;

    // 校验 since:空字符串视为拉取全部;非法字符串返回 400
    let sinceDate = new Date(0);
    if (since && since.length > 0) {
      const d = new Date(since);
      if (isNaN(d.getTime())) {
        return res.status(400).json({ error: 'Invalid since parameter' });
      }
      sinceDate = d;
    }

    // 共用 serverTime(避免 2 次 new Date() 产生微秒级漂移)
    const serverTime = new Date();

    // === 分页:每次最多返回 MAX_ITEMS_PER_PULL 条 ===
    // 客户端如果看到 has_more=true,应再用最后一条的 updatedAt 作为新的 since 继续拉
    const [books, contacts, txs, reminders] = await Promise.all([
      prisma.ledgerBook.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
        take: MAX_ITEMS_PER_PULL,
      }),
      prisma.contact.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
        take: MAX_ITEMS_PER_PULL,
      }),
      prisma.transaction.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
        take: MAX_ITEMS_PER_PULL,
      }),
      prisma.reminder.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
        take: MAX_ITEMS_PER_PULL,
      }),
    ]);

    res.setHeader('x-server-time', serverTime.toISOString());
    res.json({
      ledger_books: books.map(dtoFromBook),
      contacts:     contacts.map(dtoFromContact),
      transactions: txs.map(dtoFromTx),
      reminders:    reminders.map(dtoFromReminder),
      server_time:  serverTime.toISOString(),
      // 提示客户端是否还有更多数据(任一表 hit limit 就视为还有)
      has_more:
        books.length === MAX_ITEMS_PER_PULL ||
        contacts.length === MAX_ITEMS_PER_PULL ||
        txs.length === MAX_ITEMS_PER_PULL ||
        reminders.length === MAX_ITEMS_PER_PULL,
    });
  } catch (err) { next(err); }
});
