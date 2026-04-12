import { writeItem } from '../src/firestoreWriter';
import type { WriteItemParams } from '../src/types';

// Mock firebase-admin before any imports that use it
const mockBatchSet = jest.fn();
const mockBatchCommit = jest.fn().mockResolvedValue(undefined);
const mockBatch = { set: mockBatchSet, commit: mockBatchCommit };
const mockDoc = jest.fn((path: string) => ({ path }));
const mockCollection = jest.fn((path: string) => ({
  doc: () => ({ path: `${path}/newdoc` }),
}));

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    () => ({
      batch: () => mockBatch,
      doc: mockDoc,
      collection: mockCollection,
    }),
    {
      FieldValue: {
        serverTimestamp: () => 'SERVER_TIMESTAMP',
      },
    }
  ),
}));

const PARAMS: WriteItemParams = {
  householdId: 'hh1',
  uid: 'user1',
  name: 'milk',
  quantity: 2,
  categoryId: 'dairy-id',
};

describe('writeItem', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('calls batch.set twice (item + history)', async () => {
    await writeItem(PARAMS);
    expect(mockBatchSet).toHaveBeenCalledTimes(2);
  });

  it('commits the batch', async () => {
    await writeItem(PARAMS);
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
  });

  it('writes correct item fields', async () => {
    await writeItem(PARAMS);
    const [, itemData] = mockBatchSet.mock.calls[0];
    expect(itemData.name).toBe('milk');
    expect(itemData.quantity).toBe(2);
    expect(itemData.categoryId).toBe('dairy-id');
    expect(itemData.preferredStores).toEqual([]);
    expect(itemData.pantryItemId).toBeNull();
    expect(itemData.addedBy.source).toBe('googleHome');
    expect(itemData.addedBy.uid).toBe('user1');
    expect(itemData.addedBy.displayName).toBe('Google Home');
  });

  it('writes correct history fields', async () => {
    await writeItem(PARAMS);
    const [, histData] = mockBatchSet.mock.calls[1];
    expect(histData.itemName).toBe('milk');
    expect(histData.quantity).toBe(2);
    expect(histData.categoryId).toBe('dairy-id');
    expect(histData.action).toBe('added');
    expect(histData.byName).toBe('Google Home');
  });

  it('propagates Firestore errors', async () => {
    mockBatchCommit.mockRejectedValueOnce(new Error('Firestore unavailable'));
    await expect(writeItem(PARAMS)).rejects.toThrow('Firestore unavailable');
  });
});
