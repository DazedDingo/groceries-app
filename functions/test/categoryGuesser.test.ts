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

  it('returns Frozen for ice cream (not Dairy via cream)', () => {
    expect(guessCategoryName('ice cream')).toBe('Frozen');
  });

  describe('US/UK aliases', () => {
    it('cilantro → Produce', () => expect(guessCategoryName('cilantro')).toBe('Produce'));
    it('coriander → Produce', () => expect(guessCategoryName('coriander')).toBe('Produce'));
    it('aubergine → Produce', () => expect(guessCategoryName('aubergine')).toBe('Produce'));
    it('eggplant → Produce (beats eggs)', () =>
      expect(guessCategoryName('eggplant parmesan')).toBe('Produce'));
    it('capsicum → Produce', () => expect(guessCategoryName('capsicum')).toBe('Produce'));
    it('bell pepper → Produce', () => expect(guessCategoryName('bell pepper')).toBe('Produce'));
    it('zucchini → Produce', () => expect(guessCategoryName('zucchini')).toBe('Produce'));
    it('scallion → Produce', () => expect(guessCategoryName('scallion')).toBe('Produce'));
    it('spring onion → Produce', () => expect(guessCategoryName('spring onion')).toBe('Produce'));
    it('green onion → Produce', () => expect(guessCategoryName('green onion')).toBe('Produce'));
    it('arugula → Produce', () => expect(guessCategoryName('arugula')).toBe('Produce'));
    it('rocket → Produce', () => expect(guessCategoryName('rocket')).toBe('Produce'));
  });
});
