<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CategoryController;
use App\Http\Controllers\Api\InventoryController;
use App\Http\Controllers\Api\MedicineController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\SaleController;
use App\Http\Controllers\Api\SupplierController;
use App\Http\Controllers\Api\SettingController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\PurchaseController;
use App\Http\Controllers\Api\BarcodeCartController;
use App\Http\Controllers\Api\CaisseController;
use Illuminate\Support\Facades\Route;

// Public auth routes
Route::post('/login', [AuthController::class, 'login']);

// Protected routes
Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);

    // Admin only routes
    Route::middleware('role:admin')->group(function () {
        Route::get('/roles', [UserController::class, 'roles']);
        Route::apiResource('users', UserController::class);
    });

    // Application business logic routes
    Route::get('/settings', [SettingController::class, 'index']);
    Route::post('/settings', [SettingController::class, 'update'])->middleware('role:admin');

    Route::apiResource('categories', CategoryController::class);
    Route::apiResource('suppliers', SupplierController::class);
    Route::apiResource('medicines', MedicineController::class);
    
    // Purchases & OCR
    Route::apiResource('purchases', PurchaseController::class)->except(['update']);
    Route::post('/purchases/{purchase}/approve', [PurchaseController::class, 'approve']);

    Route::apiResource('sales', SaleController::class)->only(['index', 'store', 'show', 'destroy']);

    Route::get('/dashboard/stats', [ReportController::class, 'dashboardStats']);

    Route::prefix('inventory')->group(function () {
        Route::get('/', [InventoryController::class, 'index']);
        Route::post('/', [InventoryController::class, 'store']);
        Route::get('/low-stock', [InventoryController::class, 'lowStock']);
        Route::get('/{inventoryItem}', [InventoryController::class, 'show']);
        Route::put('/{inventoryItem}', [InventoryController::class, 'update']);
        Route::delete('/{inventoryItem}', [InventoryController::class, 'destroy']);
    });

    // Cash Register & Debt Management (Caisse & Debts)
    Route::prefix('caisse')->group(function () {
        Route::get('/stats', [CaisseController::class, 'stats']);
        Route::get('/transactions', [CaisseController::class, 'index']);
        Route::post('/transactions', [CaisseController::class, 'store']);
        Route::get('/debts', [CaisseController::class, 'debts']);
        Route::post('/debts/{debt}/pay', [CaisseController::class, 'payDebt']);
    });

    // Barcode Scanner → POS Bridge
    Route::get('/inventory/by-barcode/{barcode}', [BarcodeCartController::class, 'lookupByBarcode']);
    Route::get('/barcode-cart', [BarcodeCartController::class, 'index']);
    Route::post('/barcode-cart', [BarcodeCartController::class, 'store']);
    Route::delete('/barcode-cart', [BarcodeCartController::class, 'clear']);
});
