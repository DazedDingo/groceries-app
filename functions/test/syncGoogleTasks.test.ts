import { syncGoogleTasks, SyncDeps } from '../src/syncGoogleTasks';
import type { tasks_v1 } from 'googleapis';

// ── Mocks ────────────────────────────────────────────────────────────────────

const mockFirestoreGet = jest.fn();
const mockFirestoreSet = jest.fn().mockResolvedValue(undefined);
const mockFirestoreQuery = jest.fn();

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    () => ({
      doc: (path: string) => ({
        get: () => mockFirestoreGet(path),
        set: (data: unknown) => mockFirestoreSet(path, data),
      }),
      collection: (path: string) => ({
        where: () => ({
          limit: () => ({
            get: () => mockFirestoreQuery(path),
          }),
        }),
      }),
    }),
    { FieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' } },
  ),
}));

const mockWriteItem = jest.fn().mockResolvedValue(undefined);
jest.mock('../src/firestoreWriter', () => ({
  writeItem: (...args: unknown[]) => mockWriteItem(...args),
}));

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeTasksClient(
  tasks: Partial<tasks_v1.Schema$Task>[] = [],
  lists: Partial<tasks_v1.Schema$TaskList>[] = [{ id: 'list-1', title: 'My Tasks' }],
) {
  return {
    tasklists: {
      list: jest.fn().mockResolvedValue({ data: { items: lists } }),
    },
    tasks: {
      list: jest.fn().mockResolvedValue({ data: { items: tasks } }),
      patch: jest.fn().mockResolvedValue({}),
    },
  } as unknown as tasks_v1.Tasks;
}

function makeDeps(
  overrides: Partial<SyncDeps> & { tasks?: Partial<tasks_v1.Schema$Task>[] } = {},
): Partial<SyncDeps> {
  const client = makeTasksClient(overrides.tasks ?? []);
  return {
    getTasksClient: () => client,
    getDb: undefined, // uses mocked admin.firestore()
    uid: 'uid-123',
    listName: 'My Tasks',
    ...overrides,
    ...(overrides.getTasksClient ? {} : { getTasksClient: () => client }),
  };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('syncGoogleTasks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Default: user has household, no processed docs, no category match
    mockFirestoreGet.mockImplementation((path: string) => {
      if (path.startsWith('users/')) {
        return Promise.resolve({ data: () => ({ householdId: 'hh-1' }) });
      }
      // processed doc doesn't exist
      return Promise.resolve({ exists: false });
    });
    mockFirestoreQuery.mockResolvedValue({ empty: true, docs: [] });
  });

  it('returns synced:0 for empty task list', async () => {
    const result = await syncGoogleTasks(makeDeps({ tasks: [] }));
    expect(result).toEqual({ synced: 0, errors: 0 });
    expect(mockWriteItem).not.toHaveBeenCalled();
  });

  it('syncs a new task and writes to Firestore', async () => {
    const deps = makeDeps({ tasks: [{ id: 'task-1', title: 'milk' }] });
    const result = await syncGoogleTasks(deps);

    expect(result.synced).toBe(1);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'milk', quantity: 1, householdId: 'hh-1' }),
    );
  });

  it('parses quantity from task title', async () => {
    const deps = makeDeps({ tasks: [{ id: 'task-2', title: '3 eggs' }] });
    await syncGoogleTasks(deps);

    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'eggs', quantity: 3 }),
    );
  });

  it('marks task as processed in Firestore', async () => {
    const deps = makeDeps({ tasks: [{ id: 'task-3', title: 'bread' }] });
    await syncGoogleTasks(deps);

    expect(mockFirestoreSet).toHaveBeenCalledWith(
      'sync/googleTasks/processed/task-3',
      expect.objectContaining({ taskTitle: 'bread' }),
    );
  });

  it('marks task as completed in Google Tasks', async () => {
    const client = makeTasksClient([{ id: 'task-4', title: 'cheese' }]);
    const deps = makeDeps({ getTasksClient: () => client });
    await syncGoogleTasks(deps);

    expect(client.tasks.patch).toHaveBeenCalledWith({
      tasklist: 'list-1',
      task: 'task-4',
      requestBody: { status: 'completed' },
    });
  });

  it('skips already-processed tasks', async () => {
    mockFirestoreGet.mockImplementation((path: string) => {
      if (path.startsWith('users/')) {
        return Promise.resolve({ data: () => ({ householdId: 'hh-1' }) });
      }
      // processed doc exists
      return Promise.resolve({ exists: true });
    });

    const deps = makeDeps({ tasks: [{ id: 'task-5', title: 'butter' }] });
    const result = await syncGoogleTasks(deps);

    expect(result.synced).toBe(0);
    expect(mockWriteItem).not.toHaveBeenCalled();
  });

  it('resolves category from Firestore', async () => {
    mockFirestoreQuery.mockResolvedValue({
      empty: false,
      docs: [{ id: 'dairy-id' }],
    });

    const deps = makeDeps({ tasks: [{ id: 'task-6', title: 'milk' }] });
    await syncGoogleTasks(deps);

    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'dairy-id' }),
    );
  });

  it('falls back to uncategorised', async () => {
    const deps = makeDeps({ tasks: [{ id: 'task-7', title: 'milk' }] });
    await syncGoogleTasks(deps);

    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'uncategorised' }),
    );
  });

  it('returns errors count on write failure', async () => {
    mockWriteItem.mockRejectedValueOnce(new Error('write fail'));

    const deps = makeDeps({ tasks: [{ id: 'task-8', title: 'rice' }] });
    const result = await syncGoogleTasks(deps);

    expect(result.errors).toBe(1);
    expect(result.synced).toBe(0);
  });

  it('returns synced:0 when task list not found', async () => {
    const client = makeTasksClient([], [{ id: 'list-x', title: 'Other List' }]);
    const deps = makeDeps({ getTasksClient: () => client, listName: 'My Tasks' });
    const result = await syncGoogleTasks(deps);

    expect(result).toEqual({ synced: 0, errors: 0 });
  });

  it('returns errors when user has no household', async () => {
    mockFirestoreGet.mockImplementation((path: string) => {
      if (path.startsWith('users/')) {
        return Promise.resolve({ data: () => ({}) });
      }
      return Promise.resolve({ exists: false });
    });

    const deps = makeDeps({ tasks: [{ id: 'task-9', title: 'soup' }] });
    const result = await syncGoogleTasks(deps);

    expect(result.errors).toBe(1);
    expect(mockWriteItem).not.toHaveBeenCalled();
  });
});
