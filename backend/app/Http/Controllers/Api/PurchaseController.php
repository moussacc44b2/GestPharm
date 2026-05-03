<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Purchase;
use App\Models\PurchaseItem;
use App\Models\InventoryItem;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

class PurchaseController extends Controller
{
    public function index(Request $request)
    {
        $query = Purchase::with(['supplier', 'items.medicine']);
        
        if ($request->has('status')) {
            $query->where('status', $request->status);
        }

        return $query->latest()->paginate($request->get('per_page', 15));
    }

    public function show(Purchase $purchase)
    {
        return response()->json($purchase->load(['supplier', 'items.medicine']));
    }

    // Endpoint for Flutter App (OCR Payload)
    public function store(Request $request)
    {
        $validated = $request->validate([
            'supplier_id' => 'nullable|exists:suppliers,id',
            'invoice_number' => 'nullable|string',
            'total_amount' => 'required|numeric|min:0',
            'items' => 'required|array',
            'items.*.name' => 'required|string',
            'items.*.quantity' => 'required|integer|min:1',
            'items.*.price' => 'required|numeric|min:0',
        ]);

        DB::beginTransaction();
        try {
            $purchase = Purchase::create([
                'supplier_id' => $validated['supplier_id'] ?? null,
                'invoice_number' => $validated['invoice_number'] ?? null,
                'total_amount' => $validated['total_amount'],
                'status' => 'pending_review',
            ]);

            foreach ($validated['items'] as $item) {
                PurchaseItem::create([
                    'purchase_id' => $purchase->id,
                    'ocr_medicine_name' => $item['name'],
                    'quantity' => $item['quantity'],
                    'purchase_price' => $item['price'],
                ]);
            }

            DB::commit();
            return response()->json($purchase->load('items'), Response::HTTP_CREATED);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to store purchase from OCR'], 500);
        }
    }

    // Endpoint for Web App (Pharmacist Review & Approval)
    public function approve(Request $request, Purchase $purchase)
    {
        if ($purchase->status === 'completed') {
            return response()->json(['message' => 'Purchase is already approved'], 400);
        }

        $validated = $request->validate([
            'items' => 'required|array',
            'items.*.id' => 'required|exists:purchase_items,id',
            'items.*.medicine_id' => 'required|exists:medicines,id',
            'items.*.batch_number' => 'nullable|string',
            'items.*.expiry_date' => 'nullable|date',
        ]);

        DB::beginTransaction();
        try {
            foreach ($validated['items'] as $mappedItem) {
                $pItem = PurchaseItem::where('id', $mappedItem['id'])->where('purchase_id', $purchase->id)->firstOrFail();
                
                // Update mapped medicine
                $pItem->update([
                    'medicine_id' => $mappedItem['medicine_id']
                ]);

                // Create inventory item (stock)
                $inventoryItem = InventoryItem::create([
                    'medicine_id' => $mappedItem['medicine_id'],
                    'supplier_id' => $purchase->supplier_id,
                    'batch_number' => $mappedItem['batch_number'] ?? null,
                    'expiry_date' => $mappedItem['expiry_date'] ?? null,
                    'quantity' => $pItem->quantity,
                    'purchase_price' => $pItem->purchase_price,
                    // If selling price is unknown from OCR, default to purchase price + 20% margin, or fetch existing
                    'selling_price' => $pItem->purchase_price * 1.20, 
                ]);

                // Log movement
                \App\Models\InventoryMovement::create([
                    'inventory_item_id' => $inventoryItem->id,
                    'user_id' => $request->user()?->id,
                    'type' => 'in',
                    'quantity' => $pItem->quantity,
                    'balance_after' => $pItem->quantity,
                    'reference_type' => 'Purchase',
                    'reference_id' => $purchase->id,
                    'reason' => 'Restock from Purchase #' . ($purchase->invoice_number ?? $purchase->id),
                ]);
            }

            $purchase->update(['status' => 'completed']);

            DB::commit();
            return response()->json(['message' => 'Purchase approved and stock updated successfully', 'purchase' => $purchase->load('items.medicine')]);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to approve purchase', 'error' => $e->getMessage()], 500);
        }
    }

    public function destroy(Purchase $purchase)
    {
        if ($purchase->status === 'completed') {
            return response()->json(['message' => 'Cannot delete a completed purchase. Adjust inventory manually instead.'], 400);
        }
        
        $purchase->delete();
        return response()->json(null, Response::HTTP_NO_CONTENT);
    }
}
