import { buildHandleAddToList } from '../src/addToList';

// ── Mocks ────────────────────────────────────────────────────────────────────

const mockFirestoreGet = jest.fn();
const mockFirestoreQuery = jest.fn();
jest.mock('firebase-admin', () => ({
  firestore: () => ({
    doc: () => ({ get: mockFirestoreGet }),
    collection: () => ({
      where: () => ({ limit: () => ({ get: mockFirestoreQuery }) }),
    }),
  }),
}));

const mockWriteItem = jest.fn().mockResolvedValue(undefined);
jest.mock('../src/firestoreWriter', () => ({
  writeItem: (...args: unknown[]) => mockWriteItem(...args),
}));

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeConv(overrides: {
  user?: Partial<{ identityToken: string | undefined }>;
  params?: Partial<{ item: string; quantity: number | undefined }>;
} = {}) {
  const messages: string[] = [];
  return {
    user: { identityToken: 'valid-token', ...overrides.user },
    session: { params: { item: 'milk', quantity: undefined, ...overrides.params } },
    add: (msg: string) => { messages.push(msg); },
    _messages: messages,
  } as any;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('handleAddToList', () => {
  const handler = buildHandleAddToList({
    verifyToken: async (token: string) => {
      if (token !== 'valid-token') throw new Error('invalid');
      return 'uid-123';
    },
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockFirestoreGet.mockResolvedValue({ data: () => ({ householdId: 'hh-1' }) });
    mockFirestoreQuery.mockResolvedValue({ empty: true, docs: [] });
  });

  it('adds item with quantity 1 when quantity not specified', async () => {
    const conv = makeConv();
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'milk', quantity: 1, householdId: 'hh-1' })
    );
    expect(conv._messages[0]).toBe('Added milk to your list.');
  });

  it('adds item with specified quantity', async () => {
    const conv = makeConv({ params: { item: 'eggs', quantity: 6 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'eggs', quantity: 6 })
    );
    expect(conv._messages[0]).toBe('Added 6 eggs to your list.');
  });

  it('clamps quantity to 99 max', async () => {
    const conv = makeConv({ params: { item: 'apples', quantity: 999 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ quantity: 99 })
    );
  });

  it('clamps quantity to 1 min', async () => {
    const conv = makeConv({ params: { item: 'apples', quantity: -5 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ quantity: 1 })
    );
  });

  it('returns sign-in error when identity token is missing', async () => {
    const conv = makeConv({ user: { identityToken: undefined } });
    await handler(conv);
    expect(mockWriteItem).not.toHaveBeenCalled();
    expect(conv._messages[0]).toContain('sign in');
  });

  it('returns sign-in error when token verification fails', async () => {
    const conv = makeConv({ user: { identityToken: 'bad-token' } });
    await handler(conv);
    expect(mockWriteItem).not.toHaveBeenCalled();
    expect(conv._messages[0]).toContain('sign in');
  });

  it('returns setup error when user has no household', async () => {
    mockFirestoreGet.mockResolvedValue({ data: () => ({}) });
    const conv = makeConv();
    await handler(conv);
    expect(mockWriteItem).not.toHaveBeenCalled();
    expect(conv._messages[0]).toContain('setting up');
  });

  it('returns error when Firestore write fails', async () => {
    mockWriteItem.mockRejectedValueOnce(new Error('timeout'));
    const conv = makeConv();
    await handler(conv);
    expect(conv._messages[0]).toContain("couldn't add");
  });

  it('resolves category from Firestore when keyword matches', async () => {
    mockFirestoreQuery.mockResolvedValue({
      empty: false,
      docs: [{ id: 'dairy-cat-id' }],
    });
    const conv = makeConv({ params: { item: 'milk', quantity: 1 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'dairy-cat-id' })
    );
  });

  it('falls back to uncategorised when category not in Firestore', async () => {
    mockFirestoreQuery.mockResolvedValue({ empty: true, docs: [] });
    const conv = makeConv({ params: { item: 'milk', quantity: 1 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'uncategorised' })
    );
  });
});
