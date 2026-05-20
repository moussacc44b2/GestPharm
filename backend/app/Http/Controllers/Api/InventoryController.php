<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\InventoryItem;
use App\Models\Medicine;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class InventoryController extends Controller
{
    public function index(Request $request)
    {
        $query = InventoryItem::with(['medicine.category', 'supplier']);

        if ($request->has('medicine_id')) {
            $query->where('medicine_id', $request->medicine_id);
        }

        if ($request->has('expired')) {
            $query->where('expiry_date', '<', now());
        }

        if ($request->has('near_expiry')) {
            $query->where('expiry_date', '>', now())
                  ->where('expiry_date', '<=', now()->addDays(30));
        }

        return $query->paginate($request->get('per_page', 15));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'medicine_id' => 'required|exists:medicines,id',
            'supplier_id' => 'nullable|exists:suppliers,id',
            'batch_number' => 'nullable|string',
            'expiry_date' => 'nullable|date',
            'quantity' => 'required|integer|min:1',
            'purchase_price' => 'required|numeric|min:0',
            'selling_price' => 'required|numeric|min:0',
            'location' => 'nullable|string',
        ]);

        $item = InventoryItem::create($validated);

        return response()->json($item->load(['medicine', 'supplier']), Response::HTTP_CREATED);
    }

    public function update(Request $request, InventoryItem $inventoryItem)
    {
        $validated = $request->validate([
            'batch_number' => 'nullable|string',
            'expiry_date' => 'nullable|date',
            'quantity' => 'integer',
            'purchase_price' => 'numeric|min:0',
            'selling_price' => 'numeric|min:0',
            'location' => 'nullable|string',
        ]);

        $inventoryItem->update($validated);

        return response()->json($inventoryItem->load(['medicine', 'supplier']));
    }

    public function destroy(InventoryItem $inventoryItem)
    {
        $inventoryItem->delete();

        return response()->json(null, Response::HTTP_NO_CONTENT);
    }
    
    public function lowStock()
    {
        return Medicine::withSum('inventoryItems as total_stock', 'quantity')
            ->get()
            ->filter(function($medicine) {
                return ($medicine->total_stock ?? 0) <= $medicine->min_stock_level;
            })->values();
    }
}
