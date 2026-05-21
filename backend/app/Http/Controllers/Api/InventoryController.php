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

    public function movements(Request $request)
    {
        $query = \App\Models\InventoryMovement::with(['inventoryItem.medicine', 'user']);

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('inventory_item_id')) {
            $query->where('inventory_item_id', $request->inventory_item_id);
        }

        return $query->latest()->paginate($request->get('per_page', 15));
    }

    public function exchange(Request $request)
    {
        $validated = $request->validate([
            'mode' => 'required|in:send,receive,swap',
            'pharmacy_name' => 'required|string',
            
            // Sent item
            'sent_inventory_item_id' => 'required_if:mode,send,swap|nullable|exists:inventory_items,id',
            'sent_quantity' => 'required_if:mode,send,swap|nullable|integer|min:1',
            
            // Received item
            'received_medicine_id' => 'required_if:mode,receive,swap|nullable|exists:medicines,id',
            'received_quantity' => 'required_if:mode,receive,swap|nullable|integer|min:1',
            'received_batch_number' => 'required_if:mode,receive,swap|nullable|string',
            'received_expiry_date' => 'required_if:mode,receive,swap|nullable|date',
            'received_purchase_price' => 'required_if:mode,receive,swap|nullable|numeric|min:0',
            'received_selling_price' => 'required_if:mode,receive,swap|nullable|numeric|min:0',
            'received_location' => 'nullable|string',
            
            'notes' => 'nullable|string',
        ]);

        return \DB::transaction(function() use ($validated) {
            $user_id = auth()->id();
            $pharmacy = $validated['pharmacy_name'];
            $notes = $validated['notes'] ? " ({$validated['notes']})" : "";

            // 1. Sent Medicine
            if (in_array($validated['mode'], ['send', 'swap'])) {
                $item = InventoryItem::findOrFail($validated['sent_inventory_item_id']);
                if ($item->quantity < $validated['sent_quantity']) {
                    return response()->json([
                        'message' => 'Insufficient stock for sent medicine'
                    ], 422);
                }
                $item->decrement('quantity', $validated['sent_quantity']);

                \App\Models\InventoryMovement::create([
                    'inventory_item_id' => $item->id,
                    'user_id' => $user_id,
                    'type' => 'out',
                    'quantity' => $validated['sent_quantity'],
                    'balance_after' => $item->quantity,
                    'reason' => "Stock exchange sent to pharmacy: {$pharmacy}{$notes}",
                ]);
            }

            // 2. Received Medicine
            if (in_array($validated['mode'], ['receive', 'swap'])) {
                $item = InventoryItem::where('medicine_id', $validated['received_medicine_id'])
                    ->where('batch_number', $validated['received_batch_number'])
                    ->first();

                if ($item) {
                    $item->increment('quantity', $validated['received_quantity']);
                } else {
                    $item = InventoryItem::create([
                        'medicine_id' => $validated['received_medicine_id'],
                        'batch_number' => $validated['received_batch_number'],
                        'expiry_date' => $validated['received_expiry_date'],
                        'quantity' => $validated['received_quantity'],
                        'purchase_price' => $validated['received_purchase_price'],
                        'selling_price' => $validated['received_selling_price'],
                        'location' => $validated['received_location'] ?? null,
                    ]);
                }

                \App\Models\InventoryMovement::create([
                    'inventory_item_id' => $item->id,
                    'user_id' => $user_id,
                    'type' => 'in',
                    'quantity' => $validated['received_quantity'],
                    'balance_after' => $item->quantity,
                    'reason' => "Stock exchange received from pharmacy: {$pharmacy}{$notes}",
                ]);
            }

            return response()->json([
                'message' => 'Stock exchange registered successfully'
            ]);
        });
    }
}
