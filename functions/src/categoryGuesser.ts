const KEYWORDS: Record<string, string> = {
  // Meats
  meat: 'Meats', chicken: 'Meats', beef: 'Meats', pork: 'Meats',
  lamb: 'Meats', mince: 'Meats', steak: 'Meats', bacon: 'Meats',
  sausage: 'Meats', ham: 'Meats', turkey: 'Meats', fish: 'Meats',
  salmon: 'Meats', tuna: 'Meats', prawn: 'Meats', shrimp: 'Meats',
  // Dairy
  milk: 'Dairy', cheese: 'Dairy', butter: 'Dairy', yogurt: 'Dairy',
  yoghurt: 'Dairy', cream: 'Dairy', egg: 'Dairy', eggs: 'Dairy',
  margarine: 'Dairy', cheddar: 'Dairy',
  // Produce
  apple: 'Produce', banana: 'Produce', orange: 'Produce', grape: 'Produce',
  strawberry: 'Produce', carrot: 'Produce', potato: 'Produce',
  onion: 'Produce', tomato: 'Produce', lettuce: 'Produce',
  spinach: 'Produce', broccoli: 'Produce', pepper: 'Produce',
  cucumber: 'Produce', mushroom: 'Produce', courgette: 'Produce',
  avocado: 'Produce', lemon: 'Produce', lime: 'Produce', garlic: 'Produce',
  fruit: 'Produce', veg: 'Produce', vegetable: 'Produce', salad: 'Produce',
  // US/UK aliases — keep parity with lib/services/category_guesser.dart.
  cilantro: 'Produce', coriander: 'Produce',
  aubergine: 'Produce', eggplant: 'Produce',
  capsicum: 'Produce', 'bell pepper': 'Produce',
  zucchini: 'Produce',
  scallion: 'Produce', 'spring onion': 'Produce', 'green onion': 'Produce',
  arugula: 'Produce', rocket: 'Produce',
  // Bakery
  bread: 'Bakery', roll: 'Bakery', bun: 'Bakery', cake: 'Bakery',
  pastry: 'Bakery', croissant: 'Bakery', muffin: 'Bakery', flour: 'Bakery',
  bagel: 'Bakery', wrap: 'Bakery', pitta: 'Bakery', loaf: 'Bakery',
  // Spices
  salt: 'Spices', spice: 'Spices', herb: 'Spices', cumin: 'Spices',
  paprika: 'Spices', oregano: 'Spices', thyme: 'Spices', basil: 'Spices',
  cinnamon: 'Spices', turmeric: 'Spices', ginger: 'Spices',
  // Frozen
  frozen: 'Frozen', 'ice cream': 'Frozen', chips: 'Frozen',
  // Drinks
  water: 'Drinks', juice: 'Drinks', beer: 'Drinks', wine: 'Drinks',
  coffee: 'Drinks', tea: 'Drinks', soda: 'Drinks', cola: 'Drinks',
  squash: 'Drinks', lemonade: 'Drinks', smoothie: 'Drinks', 'orange juice': 'Drinks',
  // Household
  soap: 'Household', shampoo: 'Household', detergent: 'Household',
  cleaner: 'Household', tissue: 'Household', toilet: 'Household',
  bleach: 'Household', sponge: 'Household', 'bin bag': 'Household',
  'washing up': 'Household', toothpaste: 'Household', deodorant: 'Household',
};

// Sort once at module load — longest keyword first; ties break by insertion
// order so the result is deterministic. Mirrors lib/services/category_guesser.dart.
const SORTED_KEYWORDS: Array<[string, string]> = (() => {
  const entries = Object.entries(KEYWORDS);
  const indexOf = new Map<string, number>(entries.map(([k], i) => [k, i]));
  entries.sort((a, b) => {
    const byLen = b[0].length - a[0].length;
    if (byLen !== 0) return byLen;
    return (indexOf.get(a[0]) ?? 0) - (indexOf.get(b[0]) ?? 0);
  });
  return entries;
})();

/**
 * Returns the category name for the given item name based on keyword matching,
 * or null if no keyword matches. Mirrors lib/services/category_guesser.dart.
 */
export function guessCategoryName(itemName: string): string | null {
  const lower = itemName.toLowerCase();
  for (const [keyword, categoryName] of SORTED_KEYWORDS) {
    if (lower.includes(keyword)) return categoryName;
  }
  return null;
}
