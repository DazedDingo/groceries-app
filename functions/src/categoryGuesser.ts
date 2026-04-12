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

/**
 * Returns the category name for the given item name based on keyword matching,
 * or null if no keyword matches. Mirrors lib/services/category_guesser.dart.
 */
export function guessCategoryName(itemName: string): string | null {
  const lower = itemName.toLowerCase();
  // Sort keywords by length (longest first) to match more specific terms first
  const sortedKeywords = Object.entries(KEYWORDS).sort((a, b) => b[0].length - a[0].length);
  for (const [keyword, categoryName] of sortedKeywords) {
    if (lower.includes(keyword)) return categoryName;
  }
  return null;
}
