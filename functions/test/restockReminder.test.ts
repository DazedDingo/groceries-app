import { buildRestockMessage } from '../src/restockReminder';

describe('buildRestockMessage', () => {
  it('returns a generic body when no items are provided', () => {
    const { title, body } = buildRestockMessage([]);
    expect(title).toBe('Grocery shopping today?');
    expect(body).toBe('Check your pantry!');
  });

  it('joins the full list when it fits under the soft budget', () => {
    const { body } = buildRestockMessage(['milk', 'eggs', 'bread']);
    expect(body).toBe('milk, eggs, bread need to be bought!');
  });

  it('truncates with ", etc." when the full list overruns the budget', () => {
    const items = ['alphabetsoup', 'butterscotch', 'cinnamon', 'dragonfruit', 'elderberry'];
    const { body } = buildRestockMessage(items, 50);
    expect(body.endsWith(', etc. need to be bought!')).toBe(true);
    expect(body.length).toBeLessThanOrEqual(50);
    expect(body.startsWith('alphabetsoup')).toBe(true);
  });

  it('keeps whole item names — never splits mid-word', () => {
    const { body } = buildRestockMessage(
      ['aaaaa', 'bbbbb', 'ccccc', 'ddddd', 'eeeee'],
      35,
    );
    // Any name that appears in the body must appear in full.
    for (const part of body.replace(', etc. need to be bought!', '').split(', ')) {
      expect(['aaaaa', 'bbbbb', 'ccccc', 'ddddd', 'eeeee']).toContain(part);
    }
  });

  it('includes an over-long first item anyway rather than falling back to generic copy', () => {
    // First item alone is longer than the whole budget — keep it plus etc.
    const longName = 'a'.repeat(200);
    const { body } = buildRestockMessage([longName, 'milk'], 40);
    expect(body).toBe(`${longName}, etc. need to be bought!`);
  });

  it('is deterministic — same input yields same body', () => {
    const a = buildRestockMessage(['x', 'y', 'z'], 80);
    const b = buildRestockMessage(['x', 'y', 'z'], 80);
    expect(a).toEqual(b);
  });
});
