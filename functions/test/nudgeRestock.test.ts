import { nudgeRestock } from '../src/nudgeRestock';

// ── Mocks ────────────────────────────────────────────────────────────────────

const mockBatchSet = jest.fn();
const mockBatchUpdate = jest.fn();
const mockBatchCommit = jest.fn().mockResolvedValue(undefined);
const mockBatch = { set: mockBatchSet, update: mockBatchUpdate, commit: mockBatchCommit };

const mockPantryRefUpdate = jest.fn().mockResolvedValue(undefined);

// Tracks what collections return
const mockCollectionGet: Record<string, jest.Mock> = {};
const mockCollectionWhere: Record<string, jest.Mock> = {};

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    () => ({
      batch: () => mockBatch,
      collection: (path: string) => {
        if (path === 'households') {
          return { get: mockCollectionGet['households'] ?? jest.fn().mockResolvedValue({ docs: [] }) };
        }
        if (path.includes('/pantry')) {
          return {
            where: () => ({ get: mockCollectionGet['pantry'] ?? jest.fn().mockResolvedValue({ docs: [] }) }),
          };
        }
        if (path.includes('/items')) {
          return {
            where: () => ({ limit: () => ({ get: mockCollectionWhere['items'] ?? jest.fn().mockResolvedValue({ empty: true, docs: [] }) }) }),
            doc: () => ({ path: `${path}/newdoc` }),
          };
        }
        if (path.includes('/history')) {
          return { doc: () => ({ path: `${path}/newdoc` }) };
        }
        return { get: jest.fn().mockResolvedValue({ docs: [] }) };
      },
    }),
    { FieldValue: { serverTimestamp: () => 'SERVER_TS' } },
  ),
}));

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeHouseholdDocs(ids: string[]) {
  return { docs: ids.map(id => ({ id })) };
}

function makePantryDoc(overrides: Partial<{
  id: string;
  name: string;
  currentQuantity: number;
  optimalQuantity: number;
  restockAfterDays: number;
  lastNudgedAt: { toDate: () => Date } | null;
  lastPurchasedAt: { toDate: () => Date } | null;
  categoryId: string;
}> = {}) {
  const data = {
    name: 'milk',
    currentQuantity: 0,
    optimalQuantity: 2,
    restockAfterDays: 7,
    lastNudgedAt: null,
    lastPurchasedAt: null,
    categoryId: 'dairy',
    ...overrides,
  };
  return {
    id: overrides.id ?? 'pantry-1',
    data: () => data,
    ref: { update: mockPantryRefUpdate },
  };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('nudgeRestock', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockBatchCommit.mockResolvedValue(undefined);
    mockCollectionWhere['items'] = jest.fn().mockResolvedValue({ empty: true, docs: [] });
  });

  it('returns nudged:0 when no households exist', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue({ docs: [] });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(0);
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  it('skips item that is at or above optimal', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc({ currentQuantity: 3, optimalQuantity: 2 })],
    });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(0);
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  it('skips item when not enough days have passed since lastNudgedAt', async () => {
    const recentDate = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000); // 2 days ago
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc({ restockAfterDays: 7, lastNudgedAt: { toDate: () => recentDate } })],
    });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(0);
  });

  it('nudges item when no lastNudgedAt and no lastPurchasedAt (defaults to epoch)', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc({ lastNudgedAt: null, lastPurchasedAt: null })],
    });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(1);
    expect(mockBatchSet).toHaveBeenCalledTimes(2); // item + history
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
  });

  it('nudges item when enough days have passed since lastPurchasedAt', async () => {
    const oldDate = new Date(Date.now() - 10 * 24 * 60 * 60 * 1000); // 10 days ago
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc({ restockAfterDays: 7, lastPurchasedAt: { toDate: () => oldDate } })],
    });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(1);
  });

  it('writes correct quantity (optimal - current) to shopping list', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc({ currentQuantity: 1, optimalQuantity: 4 })],
    });
    await nudgeRestock();
    const [, itemData] = mockBatchSet.mock.calls[0];
    expect(itemData.quantity).toBe(3); // 4 - 1
    expect(itemData.name).toBe('milk');
    expect(itemData.addedBy.source).toBe('app');
    expect(itemData.addedBy.displayName).toBe('Restock nudge');
  });

  it('skips item and updates lastNudgedAt when already on shopping list', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc()],
    });
    mockCollectionWhere['items'] = jest.fn().mockResolvedValue({
      empty: false,
      docs: [{ id: 'existing-item' }],
    });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(0);
    expect(mockBatchCommit).not.toHaveBeenCalled();
    expect(mockPantryRefUpdate).toHaveBeenCalledWith({ lastNudgedAt: 'SERVER_TS' });
  });

  it('handles multiple households independently', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1', 'hh-2']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc()],
    });
    const result = await nudgeRestock();
    expect(result.nudged).toBe(2);
    expect(mockBatchCommit).toHaveBeenCalledTimes(2);
  });

  it('links item to pantry via pantryItemId', async () => {
    mockCollectionGet['households'] = jest.fn().mockResolvedValue(makeHouseholdDocs(['hh-1']));
    mockCollectionGet['pantry'] = jest.fn().mockResolvedValue({
      docs: [makePantryDoc({ id: 'pantry-abc' })],
    });
    await nudgeRestock();
    const [, itemData] = mockBatchSet.mock.calls[0];
    expect(itemData.pantryItemId).toBe('pantry-abc');
  });
});
