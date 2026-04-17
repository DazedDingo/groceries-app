import { handleIftttWebhook, parseItemString } from '../src/addToList';

// ── Mocks ────────────────────────────────────────────────────────────────────

const mockFirestoreGet = jest.fn();
const mockFirestoreQuery = jest.fn();
const mockFirestoreSet = jest.fn().mockResolvedValue(undefined);
const mockDocPath = jest.fn<unknown, [string]>();
jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    () => ({
      doc: (path: string) => {
        mockDocPath(path);
        return { get: mockFirestoreGet, set: mockFirestoreSet };
      },
      collection: () => ({
        where: () => ({ limit: () => ({ get: mockFirestoreQuery }) }),
      }),
    }),
    {
      FieldValue: {
        serverTimestamp: () => '__ts__',
      },
    },
  ),
}));

const mockWriteItem = jest.fn().mockResolvedValue(undefined);
jest.mock('../src/firestoreWriter', () => ({
  writeItem: (...args: unknown[]) => mockWriteItem(...args),
}));

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeReq(overrides: {
  body?: Record<string, unknown>;
  query?: Record<string, string>;
  headers?: Record<string, string>;
} = {}) {
  return {
    method: 'POST',
    body: { item: 'milk', ...overrides.body },
    query: { key: 'test-secret', ...overrides.query },
    headers: { ...overrides.headers },
  };
}

function makeRes() {
  const res: any = {
    _status: 0,
    _body: null,
  };
  res.status = (code: number) => { res._status = code; return res; };
  res.json = (data: unknown) => { res._body = data; };
  res.send = (data: string) => { res._body = data; };
  return res;
}

const deps = {
  getSecret: () => 'test-secret',
  getUserUid: () => 'uid-123',
};

// ── parseItemString ──────────────────────────────────────────────────────────

describe('parseItemString', () => {
  it('parses "3 eggs" into quantity 3, name "eggs"', () => {
    expect(parseItemString('3 eggs')).toEqual({ quantity: 3, name: 'eggs' });
  });

  it('defaults to quantity 1 when no number prefix', () => {
    expect(parseItemString('milk')).toEqual({ quantity: 1, name: 'milk' });
  });

  it('clamps quantity to 99 max', () => {
    expect(parseItemString('999 apples')).toEqual({ quantity: 99, name: 'apples' });
  });

  it('clamps quantity to 1 min', () => {
    expect(parseItemString('0 apples')).toEqual({ quantity: 1, name: 'apples' });
  });

  it('trims whitespace', () => {
    expect(parseItemString('  2  bananas  ')).toEqual({ quantity: 2, name: 'bananas' });
  });

  it('parses "pounds of" and returns unit', () => {
    expect(parseItemString('2 pounds of cheese')).toEqual({ quantity: 2, name: 'cheese', unit: 'lb' });
  });

  it('parses "bags of" and returns unit', () => {
    expect(parseItemString('3 bags of spinach')).toEqual({ quantity: 3, name: 'spinach', unit: 'bags' });
  });

  it('parses singular "bottle of" and returns unit', () => {
    expect(parseItemString('1 bottle of wine')).toEqual({ quantity: 1, name: 'wine', unit: 'bottles' });
  });

  it('parses "dozen" and returns unit', () => {
    expect(parseItemString('2 dozen eggs')).toEqual({ quantity: 2, name: 'eggs', unit: 'dozen' });
  });

  it('parses "lb" shorthand and returns unit', () => {
    expect(parseItemString('5 lb ground beef')).toEqual({ quantity: 5, name: 'ground beef', unit: 'lb' });
  });

  it('parses "g" unit', () => {
    expect(parseItemString('300 g flour')).toEqual({ quantity: 300, name: 'flour', unit: 'g' });
  });

  it('keeps name without unit when no unit match', () => {
    const result = parseItemString('3 eggs');
    expect(result.quantity).toBe(3);
    expect(result.name).toBe('eggs');
    expect(result.unit).toBeUndefined();
  });
});

// ── handleIftttWebhook ───────────────────────────────────────────────────────

describe('handleIftttWebhook', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockFirestoreGet.mockResolvedValue({ data: () => ({ householdId: 'hh-1' }) });
    mockFirestoreQuery.mockResolvedValue({ empty: true, docs: [] });
  });

  it('returns 401 when secret is wrong', async () => {
    const req = makeReq({ query: { key: 'wrong' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(401);
    expect(mockWriteItem).not.toHaveBeenCalled();
  });

  it('returns 401 when no secret provided', async () => {
    const req = makeReq({ query: { key: '' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(401);
  });

  it('accepts secret via Authorization bearer header', async () => {
    const req = makeReq({
      query: {},
      headers: { authorization: 'Bearer test-secret' },
    });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(200);
  });

  it('returns 400 when item is missing', async () => {
    const req = makeReq({ body: { item: '' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(400);
  });

  it('adds item with quantity 1 for plain name', async () => {
    const req = makeReq({ body: { item: 'milk' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(200);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'milk', quantity: 1, householdId: 'hh-1' })
    );
  });

  it('parses quantity from item string like "3 eggs"', async () => {
    const req = makeReq({ body: { item: '3 eggs' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'eggs', quantity: 3 })
    );
  });

  it('reads IFTTT value1 field as fallback', async () => {
    const req = makeReq({ body: { item: undefined, value1: 'bread' } as any });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'bread', quantity: 1 })
    );
  });

  it('returns 500 when user has no household', async () => {
    mockFirestoreGet.mockResolvedValue({ data: () => ({}) });
    const req = makeReq();
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(500);
    expect(res._body).toEqual({ error: 'User has no household' });
  });

  it('returns 500 when Firestore write fails', async () => {
    mockWriteItem.mockRejectedValueOnce(new Error('timeout'));
    const req = makeReq();
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._status).toBe(500);
    expect(res._body).toEqual({ error: 'Failed to write item' });
  });

  it('resolves category from Firestore when keyword matches', async () => {
    mockFirestoreQuery.mockResolvedValue({
      empty: false,
      docs: [{ id: 'dairy-cat-id' }],
    });
    const req = makeReq({ body: { item: 'milk' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'dairy-cat-id' })
    );
  });

  it('falls back to uncategorised when category not in Firestore', async () => {
    const req = makeReq({ body: { item: 'milk' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'uncategorised' })
    );
  });

  it('returns success JSON with item details', async () => {
    const req = makeReq({ body: { item: '2 eggs' } });
    const res = makeRes();
    await handleIftttWebhook(req, res, deps);
    expect(res._body).toEqual(
      expect.objectContaining({ ok: true, name: 'eggs', quantity: 2 })
    );
  });

  describe('webhookStatus recording', () => {
    it('records lastWebhookAt + last item name on success', async () => {
      mockFirestoreSet.mockClear();
      mockDocPath.mockClear();
      const req = makeReq({ body: { item: '2 eggs' } });
      const res = makeRes();
      await handleIftttWebhook(req, res, deps);
      expect(res._status).toBe(200);
      expect(mockDocPath).toHaveBeenCalledWith(
        'households/hh-1/config/webhookStatus',
      );
      expect(mockFirestoreSet).toHaveBeenCalledWith(
        expect.objectContaining({
          lastWebhookAt: '__ts__',
          lastItemName: 'eggs',
          lastQuantity: 2,
        }),
        { merge: true },
      );
    });

    it('still returns 200 if webhookStatus write fails', async () => {
      mockFirestoreSet.mockRejectedValueOnce(new Error('status write boom'));
      const req = makeReq({ body: { item: 'bread' } });
      const res = makeRes();
      await handleIftttWebhook(req, res, deps);
      expect(res._status).toBe(200);
    });

    it('does NOT write status when writeItem fails', async () => {
      mockWriteItem.mockRejectedValueOnce(new Error('boom'));
      mockFirestoreSet.mockClear();
      const req = makeReq();
      const res = makeRes();
      await handleIftttWebhook(req, res, deps);
      expect(res._status).toBe(500);
      expect(mockFirestoreSet).not.toHaveBeenCalled();
    });
  });
});
