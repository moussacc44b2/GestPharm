<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\InventoryItem;
use App\Models\Sale;
use App\Models\SaleItem;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

class SaleController extends Controller
{
    public function index(Request $request)
    {
        $query = Sale::with(['items.inventoryItem.medicine', 'user']);

        if ($request->has('start_date') && $request->has('end_date')) {
            $query->whereBetween('created_at', [$request->start_date, $request->end_date]);
        }

        return $query->latest()->paginate($request->get('per_page', 15));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'customer_name' => 'nullable|string',
            'amount_paid' => 'required|numeric|min:0',
            'payment_method' => 'required|string',
            'items' => 'required|array|min:1',
            'items.*.inventory_item_id' => 'required|exists:inventory_items,id',
            'items.*.quantity' => 'required|integer|min:1',
            'notes' => 'nullable|string',
        ]);

        return DB::transaction(function () use ($validated, $request) {
            $totalAmount = 0;
            $saleItems = [];

            foreach ($validated['items'] as $itemData) {
                $inventoryItem = InventoryItem::lockForUpdate()->find($itemData['inventory_item_id']);

                if ($inventoryItem->quantity < $itemData['quantity']) {
                    throw new \Exception("Insufficient stock for medicine: {$inventoryItem->medicine->name}");
                }

                $itemTotal = $inventoryItem->selling_price * $itemData['quantity'];
                $totalAmount += $itemTotal;

                $saleItems[] = new SaleItem([
                    'inventory_item_id' => $inventoryItem->id,
                    'quantity' => $itemData['quantity'],
                    'unit_price' => $inventoryItem->selling_price,
                    'total_price' => $itemTotal,
                ]);

                // Update stock
                $inventoryItem->decrement('quantity', $itemData['quantity']);

                // Log movement
                \App\Models\InventoryMovement::create([
                    'inventory_item_id' => $inventoryItem->id,
                    'user_id' => $request->user()?->id,
                    'type' => 'out',
                    'quantity' => $itemData['quantity'],
                    'balance_after' => $inventoryItem->fresh()->quantity,
                    'reference_type' => 'Sale',
                    'reference_id' => null, // Will update after sale is created
                    'reason' => 'Sale Transaction',
                ]);
            }

            $changeAmount = $validated['amount_paid'] - $totalAmount;

            $sale = Sale::create([
                'user_id' => $request->user()?->id,
                'customer_name' => $validated['customer_name'],
                'total_amount' => $totalAmount,
                'amount_paid' => $validated['amount_paid'],
                'change_amount' => max(0, $changeAmount),
                'payment_method' => $validated['payment_method'],
                'status' => 'completed',
                'notes' => $validated['notes'],
            ]);

            $sale->items()->saveMany($saleItems);

            // Update movement reference_id
            \App\Models\InventoryMovement::where('reference_type', 'Sale')
                ->whereNull('reference_id')
                ->where('user_id', $request->user()?->id)
                ->update(['reference_id' => $sale->id]);

            return response()->json($sale->load('items.inventoryItem.medicine'), Response::HTTP_CREATED);
        });
    }

    public function show(Sale $sale)
    {
        return $sale->load(['items.inventoryItem.medicine', 'user']);
    }
}
