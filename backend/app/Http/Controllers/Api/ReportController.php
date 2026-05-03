<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\InventoryItem;
use App\Models\Medicine;
use App\Models\Sale;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ReportController extends Controller
{
    public function dashboardStats()
    {
        $totalMedicines = Medicine::count();
        $totalStock = InventoryItem::sum('quantity');
        $todaySales = Sale::whereDate('created_at', today())->sum('total_amount');
        
        $lowStockCount = Medicine::whereHas('inventoryItems', function($q) {
            // Simplified for now
        })->get()->filter(function($m) {
            return $m->total_stock <= $m->min_stock_level;
        })->count();

        // Recent sales for chart
        $salesHistory = Sale::select(
            DB::raw('DATE(created_at) as date'),
            DB::raw('SUM(total_amount) as total')
        )
        ->where('created_at', '>=', now()->subDays(7))
        ->groupBy('date')
        ->orderBy('date')
        ->get();

        return response()->json([
            'stats' => [
                'total_medicines' => $totalMedicines,
                'total_stock' => $totalStock,
                'today_sales' => $todaySales,
                'low_stock_alerts' => $lowStockCount,
            ],
            'sales_history' => $salesHistory,
        ]);
    }
}
