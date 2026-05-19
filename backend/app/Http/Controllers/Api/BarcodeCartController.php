<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BarcodeScan;
use App\Models\InventoryItem;
use App\Models\Medicine;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class BarcodeCartController extends Controller
{
    /**
     * Lookup inventory item by medicine barcode.
     * GET /api/inventory/by-barcode/{barcode}
     */
    public function lookupByBarcode(string $barcode)
    {
        $medicine = Medicine::where('barcode', $barcode)->first();

        // Get the first available inventory item with stock > 0 matching barcode on medicine or inventory_item
        $query = InventoryItem::query();
        if ($medicine) {
            $query->where(function ($q) use ($medicine, $barcode) {
                $q->where('medicine_id', $medicine->id)
                  ->orWhere('barcode', $barcode);
            });
        } else {
            $query->where('barcode', $barcode);
        }

        $inventoryItem = $query->where('quantity', '>', 0)
            ->with(['medicine.category', 'supplier'])
            ->orderBy('expiry_date', 'asc') // FEFO: First Expiry, First Out
            ->first();

        if (!$inventoryItem) {
            if (!$medicine) {
                return response()->json([
                    'message' => 'Medicine not found in database.',
                ], Response::HTTP_NOT_FOUND);
            }

            return response()->json([
                'message' => 'Medicine found but no stock available.',
                'medicine' => $medicine,
            ], Response::HTTP_NOT_FOUND);
        }

        return response()->json($inventoryItem);
    }

    /**
     * Push a scanned item to the barcode cart.
     * POST /api/barcode-cart
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'inventory_item_id' => 'nullable|exists:inventory_items,id',
            'barcode' => 'nullable|string',
            'quantity' => 'integer|min:1',
        ]);

        $inventoryItemId = $validated['inventory_item_id'] ?? null;

        if (empty($inventoryItemId) && !empty($validated['barcode'])) {
            $barcode = $validated['barcode'];
            $medicine = Medicine::where('barcode', $barcode)->first();

            // Find first available inventory item with stock > 0 matching barcode on medicine or inventory_item
            $query = InventoryItem::query();
            if ($medicine) {
                $query->where(function ($q) use ($medicine, $barcode) {
                    $q->where('medicine_id', $medicine->id)
                      ->orWhere('barcode', $barcode);
                });
            } else {
                $query->where('barcode', $barcode);
            }

            $inventoryItem = $query->where('quantity', '>', 0)
                ->orderBy('expiry_date', 'asc') // FEFO
                ->first();

            if (!$inventoryItem) {
                if (!$medicine) {
                    return response()->json([
                        'message' => 'Medicine not found in database.',
                    ], Response::HTTP_NOT_FOUND);
                }
                return response()->json([
                    'message' => 'Medicine found but no stock available.',
                ], Response::HTTP_NOT_FOUND);
            }

            $inventoryItemId = $inventoryItem->id;
        }

        if (empty($inventoryItemId)) {
            return response()->json([
                'message' => 'The inventory item id or barcode field is required.',
            ], 422);
        }

        $scan = BarcodeScan::create([
            'inventory_item_id' => $inventoryItemId,
            'user_id' => $request->user()->id,
            'quantity' => $validated['quantity'] ?? 1,
        ]);

        return response()->json($scan->load('inventoryItem.medicine'), Response::HTTP_CREATED);
    }

    /**
     * Get unprocessed scanned items for the current user.
     * GET /api/barcode-cart
     */
    public function index(Request $request)
    {
        $items = BarcodeScan::where('user_id', $request->user()->id)
            ->where('processed', false)
            ->with(['inventoryItem.medicine'])
            ->latest()
            ->get();

        return response()->json($items);
    }

    /**
     * Mark all items as processed (clear the cart).
     * DELETE /api/barcode-cart
     */
    public function clear(Request $request)
    {
        BarcodeScan::where('user_id', $request->user()->id)
            ->where('processed', false)
            ->update(['processed' => true]);

        return response()->json(null, Response::HTTP_NO_CONTENT);
    }
}
