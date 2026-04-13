import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/meal_plan.dart';
import '../services/meal_plan_service.dart';
import 'household_provider.dart';

final mealPlanServiceProvider = Provider<MealPlanService>(
  (ref) => MealPlanService(),
);

final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return now.subtract(Duration(days: now.weekday - 1)); // Monday
});

final mealPlanProvider = StreamProvider<List<MealPlanEntry>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  final weekStart = ref.watch(selectedWeekStartProvider);
  if (householdId == null) return const Stream.empty();
  return ref.watch(mealPlanServiceProvider).weekStream(householdId, weekStart);
});
