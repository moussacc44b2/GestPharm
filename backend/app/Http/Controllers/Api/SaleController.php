<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\InventoryItem;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\CashTransaction;
use App\Models\Debt;
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
            $inventoryItemIds = collect($validated['items'])->pluck('inventory_item_id');
            // Pre-fetch and lock all inventory items with their medicines in exactly 1 query
            $inventoryItems = InventoryItem::with('medicine')->lockForUpdate()->whereIn('id', $inventoryItemIds)->get()->keyBy('id');

            $totalAmount = 0;
            
            // First loop: Validate stock levels and calculate total amount
            foreach ($validated['items'] as $itemData) {
                $inventoryItem = $inventoryItems->get($itemData['inventory_item_id']);
                if (!$inventoryItem) {
                    throw new \Exception("Inventory item not found.");
                }

                if ($inventoryItem->quantity < $itemData['quantity']) {
                    throw new \Exception("Insufficient stock for medicine: {$inventoryItem->medicine->name}");
                }

                $totalAmount += $inventoryItem->selling_price * $itemData['quantity'];
            }

            $changeAmount = $validated['amount_paid'] - $totalAmount;

            // Create the sale record first
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

            $saleItems = [];

            // Second loop: Update quantities, create sale items, and write inventory movements with direct reference_id
            foreach ($validated['items'] as $itemData) {
                $inventoryItem = $inventoryItems->get($itemData['inventory_item_id']);
                $itemTotal = $inventoryItem->selling_price * $itemData['quantity'];

                $saleItems[] = new SaleItem([
                    'inventory_item_id' => $inventoryItem->id,
                    'quantity' => $itemData['quantity'],
                    'unit_price' => $inventoryItem->selling_price,
                    'total_price' => $itemTotal,
                ]);

                // Update stock in database
                $newQuantity = $inventoryItem->quantity - $itemData['quantity'];
                $inventoryItem->update(['quantity' => $newQuantity]);

                // Log movement directly with sale->id (no bulk update needed, no race conditions)
                \App\Models\InventoryMovement::create([
                    'inventory_item_id' => $inventoryItem->id,
                    'user_id' => $request->user()?->id,
                    'type' => 'out',
                    'quantity' => $itemData['quantity'],
                    'balance_after' => $newQuantity,
                    'reference_type' => 'Sale',
                    'reference_id' => $sale->id,
                    'reason' => 'Sale Transaction',
                ]);
            }

            $sale->items()->saveMany($saleItems);

            // Record cash register inflow based on actual received cash (amount_paid - change_amount)
            $actualReceived = $sale->amount_paid - $sale->change_amount;
            if ($actualReceived > 0) {
                CashTransaction::create([
                    'user_id' => $request->user()?->id,
                    'type' => 'inflow',
                    'amount' => $actualReceived,
                    'category' => 'sale',
                    'description' => 'Sale Transaction #' . $sale->id,
                    'reference_type' => Sale::class,
                    'reference_id' => $sale->id,
                ]);
            }

            // Create customer debt if actual received cash is less than the sale total
            if ($actualReceived < $sale->total_amount) {
                $remainingDebt = $sale->total_amount - $actualReceived;
                if ($remainingDebt > 0) {
                    Debt::create([
                        'type' => 'customer',
                        'customer_name' => $sale->customer_name ?: 'Walk-in Customer',
                        'sale_id' => $sale->id,
                        'total_amount' => $sale->total_amount,
                        'paid_amount' => $actualReceived,
                        'status' => ($actualReceived > 0) ? 'partially_paid' : 'unpaid',
                        'due_date' => now()->addDays(30),
                    ]);
                }
            }

            return response()->json($sale->load('items.inventoryItem.medicine'), Response::HTTP_CREATED);
        });
    }

    public function show(Sale $sale)
    {
        return $sale->load(['items.inventoryItem.medicine', 'user']);
    }

    public function destroy(Sale $sale, Request $request)
    {
        return DB::transaction(function () use ($sale, $request) {
            // Load items explicitly before deleting to ensure they are fetched
            $sale->load('items.inventoryItem');

            foreach ($sale->items as $item) {
                $inventoryItem = $item->inventoryItem;
                if ($inventoryItem) {
                    // Lock for update to avoid race conditions
                    $inventoryItem = InventoryItem::lockForUpdate()->find($inventoryItem->id);
                    $inventoryItem->increment('quantity', $item->quantity);

                    // Log inventory movement
                    \App\Models\InventoryMovement::create([
                        'inventory_item_id' => $inventoryItem->id,
                        'user_id' => $request->user()?->id,
                        'type' => 'in',
                        'quantity' => $item->quantity,
                        'balance_after' => $inventoryItem->fresh()->quantity,
                        'reference_type' => 'Sale Deletion',
                        'reference_id' => $sale->id,
                        'reason' => 'Sale Cancelled/Deleted #' . $sale->id,
                    ]);
                }
            }

            // Delete cash transactions and debts associated with this sale
            CashTransaction::where('reference_type', Sale::class)
                ->where('reference_id', $sale->id)
                ->delete();

            Debt::where('sale_id', $sale->id)->delete();

            $sale->delete();

            return response()->json(['message' => 'Sale deleted and inventory restored successfully.']);
        });
    }
}
