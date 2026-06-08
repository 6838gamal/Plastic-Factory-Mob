class AppConstants {
  // Deviation threshold percentage
  static const double deviationThreshold = 2.0;

  // Waste threshold percentage
  static const double wasteHighThreshold = 5.0;

  // Scrap threshold percentage
  static const double scrapHighThreshold = 10.0;

  // Low stock percentage (below this = low stock warning)
  static const double lowStockThreshold = 20.0;

  // Table names
  static const String tbRawMaterials = 'raw_materials';
  static const String tbInventory = 'inventory';
  static const String tbInventoryTransactions = 'inventory_transactions';
  static const String tbWorkers = 'workers';
  static const String tbProducts = 'products';
  static const String tbMachines = 'machines';
  static const String tbMixers = 'mixers';
  static const String tbShifts = 'shifts';
  static const String tbMixtureTypes = 'mixture_types';
  static const String tbBatches = 'batches';
  static const String tbBatchMaterials = 'batch_materials';
  static const String tbMachineProduction = 'machine_production';
  static const String tbAlerts = 'alerts';
  static const String tbAuditLog = 'audit_log';
  static const String tbRecipes = 'recipes';
  static const String tbRecipeItems = 'recipe_items';

  // Warehouse types
  static const String warehouseMain = 'main';
  static const String warehouseMixer = 'mixer';

  // Alert severities
  static const String severityCritical = 'critical';
  static const String severityHigh = 'high';
  static const String severityMedium = 'medium';
  static const String severityLow = 'low';

  // Alert statuses
  static const String alertPending = 'pending';
  static const String alertAcknowledged = 'acknowledged';
  static const String alertResolved = 'resolved';

  // Audit actions
  static const String auditCreate = 'create';
  static const String auditUpdate = 'update';
  static const String auditDelete = 'delete';
  static const String auditDeduct = 'deduct';
  static const String auditTransfer = 'transfer';
  static const String auditFailed = 'failed';

  // Hive box names
  static const String boxPendingBatches = 'pending_batches';
  static const String boxPendingProduction = 'pending_production';
  static const String boxSettings = 'settings';
  static const String boxCache = 'cache';

  // Units
  static const List<String> units = ['كجم', 'لتر', 'طن', 'جرام', 'قطعة'];

  // Default shifts
  static const List<String> defaultShifts = [
    'الصباحية',
    'المسائية',
    'الليلية',
  ];
}
