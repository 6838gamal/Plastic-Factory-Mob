/// Default data seeded on first run.
/// Edit these lists to match your factory's actual setup.
/// Changes made in the admin panel override these defaults.

class SeedData {
  static const List<Map<String, dynamic>> workers = [
    {'id': 'seed-w-1', 'name': 'رضوان', 'is_active': true},
    {'id': 'seed-w-2', 'name': 'صقر', 'is_active': true},
  ];

  static const List<Map<String, dynamic>> machines = [
    {'id': 'seed-m-1', 'name': 'ماكينة 1', 'is_active': true},
    {'id': 'seed-m-2', 'name': 'ماكينة 2', 'is_active': true},
    {'id': 'seed-m-3', 'name': 'ماكينة 3', 'is_active': true},
    {'id': 'seed-m-4', 'name': 'ماكينة 4', 'is_active': true},
  ];

  static const List<Map<String, dynamic>> mixers = [
    {'id': 'seed-x-1', 'name': 'خلاط 1', 'is_active': true},
    {'id': 'seed-x-2', 'name': 'خلاط 2', 'is_active': true},
  ];

  static const List<Map<String, dynamic>> products = [
    {'id': 'seed-p-1', 'name': 'صندل رجالي', 'is_active': true},
    {'id': 'seed-p-2', 'name': 'صندل ولادي', 'is_active': true},
  ];

  static const List<Map<String, dynamic>> mixtureTypes = [
    {'id': 'seed-t-1', 'name': 'خلطة سوداء', 'is_active': true},
    {'id': 'seed-t-2', 'name': 'خلطة زرقاء', 'is_active': true},
  ];

  static const List<Map<String, dynamic>> batchTypes = [];
}
