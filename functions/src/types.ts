export interface WriteItemParams {
  householdId: string;
  uid: string;
  name: string;
  quantity: number;
  unit?: string;
  categoryId: string;
}
