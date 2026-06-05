// POST /sync/push  +  GET /sync/pull?since=ISO_DATE
import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';

export const syncRoutes = Router();
syncRoutes.use(requireAuth);

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

    // Process in dependency order:Contacts & Books first, then Transactions
    const bookMappings = await Promise.all(ledgerBooks.map(async (b) => {
      const data = {
        title: b.title,
        categoryRaw: b.categoryRaw,
        directionRaw: b.directionRaw,
        eventDate: new Date(b.eventDate),
        note: b.note ?? '',
        coverColorHex: b.coverColorHex ?? '#FF6B6B',
        isClosed: !!b.isClosed,
        deletedAt: b.deletedAt ? new Date(b.deletedAt) : null,
      };
      const row = await prisma.ledgerBook.upsert({
        where: { userId_clientId: { userId, clientId: b.clientId } },
        create: { ...data, userId, clientId: b.clientId },
        update: data,
      });
      return { clientId: b.clientId, serverId: row.id };
    }));

    const contactMappings = await Promise.all(contacts.map(async (c) => {
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
      const row = await prisma.contact.upsert({
        where: { userId_clientId: { userId, clientId: c.clientId } },
        create: { ...data, userId, clientId: c.clientId },
        update: data,
      });
      return { clientId: c.clientId, serverId: row.id };
    }));

    const txMappings = await Promise.all(transactions.map(async (t) => {
      // Resolve foreign book / contact via clientId
      let bookId: string | null = null;
      let contactId: string | null = null;
      if (t.bookClientId) {
        const b = await prisma.ledgerBook.findUnique({
          where: { userId_clientId: { userId, clientId: t.bookClientId } },
        });
        bookId = b?.id ?? null;
      }
      if (t.contactClientId) {
        const c = await prisma.contact.findUnique({
          where: { userId_clientId: { userId, clientId: t.contactClientId } },
        });
        contactId = c?.id ?? null;
      }
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
      const row = await prisma.transaction.upsert({
        where: { userId_clientId: { userId, clientId: t.clientId } },
        create: { ...data, userId, clientId: t.clientId },
        update: data,
      });
      return { clientId: t.clientId, serverId: row.id };
    }));

    const reminderMappings = await Promise.all(reminders.map(async (r) => {
      const data = {
        title: r.title,
        date: new Date(r.date),
        useLunar: !!r.useLunar,
        advanceDays: r.advanceDays ?? 7,
        note: r.note ?? '',
        colorHex: r.colorHex ?? '#FF6B6B',
        isEnabled: r.isEnabled !== false,
        deletedAt: r.deletedAt ? new Date(r.deletedAt) : null,
      };
      const row = await prisma.reminder.upsert({
        where: { userId_clientId: { userId, clientId: r.clientId } },
        create: { ...data, userId, clientId: r.clientId },
        update: data,
      });
      return { clientId: r.clientId, serverId: row.id };
    }));

    res.json({
      ledger_books:  bookMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
      contacts:      contactMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
      transactions:  txMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
      reminders:     reminderMappings.map(m => ({ client_id: m.clientId, server_id: m.serverId })),
    });
  } catch (err) { next(err); }
});

// ===== GET /sync/pull?since=ISO_DATE =====
// Returns all rows where updatedAt > since(or all if since empty)
syncRoutes.get('/pull', async (req, res, next) => {
  try {
    const userId = req.user!.sub;
    const since = req.query.since as string | undefined;
    const sinceDate = since && since.length > 0 ? new Date(since) : new Date(0);

    const [books, contacts, txs, reminders] = await Promise.all([
      prisma.ledgerBook.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
      }),
      prisma.contact.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
      }),
      prisma.transaction.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
      }),
      prisma.reminder.findMany({
        where: { userId, updatedAt: { gt: sinceDate } },
        orderBy: { updatedAt: 'asc' },
      }),
    ]);

    res.setHeader('x-server-time', new Date().toISOString());
    res.json({
      ledger_books: books.map(dtoFromBook),
      contacts:     contacts.map(dtoFromContact),
      transactions: txs.map(dtoFromTx),
      reminders:    reminders.map(dtoFromReminder),
      server_time:  new Date().toISOString(),
    });
  } catch (err) { next(err); }
});
