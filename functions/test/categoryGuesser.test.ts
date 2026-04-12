import { guessCategoryName } from '../src/categoryGuesser';

describe('guessCategoryName', () => {
  it('returns Dairy for milk', () => {
    expect(guessCategoryName('milk')).toBe('Dairy');
  });

  it('returns Meats for chicken breast', () => {
    expect(guessCategoryName('chicken breast')).toBe('Meats');
  });

  it('returns Produce for courgettes (partial match)', () => {
    expect(guessCategoryName('courgettes')).toBe('Produce');
  });

  it('is case-insensitive', () => {
    expect(guessCategoryName('MILK')).toBe('Dairy');
    expect(guessCategoryName('Eggs')).toBe('Dairy');
  });

  it('returns null for unknown items', () => {
    expect(guessCategoryName('gkflrb')).toBeNull();
  });

  it('returns Drinks for orange juice', () => {
    expect(guessCategoryName('orange juice')).toBe('Drinks');
  });

  it('returns Bakery for sourdough bread', () => {
    expect(guessCategoryName('sourdough bread')).toBe('Bakery');
  });

  it('returns Household for washing up liquid', () => {
    expect(guessCategoryName('washing up liquid')).toBe('Household');
  });
});
