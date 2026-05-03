<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Medicine;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class MedicineController extends Controller
{
    public function index(Request $request)
    {
        $query = Medicine::with('category');

        if ($request->has('category_id')) {
            $query->where('category_id', $request->category_id);
        }

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('generic_name', 'like', "%{$search}%")
                  ->orWhere('sku', 'like', "%{$search}%")
                  ->orWhere('barcode', 'like', "%{$search}%");
            });
        }

        return $query->paginate($request->get('per_page', 15));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string',
            'generic_name' => 'nullable|string',
            'sku' => 'nullable|string|unique:medicines,sku',
            'barcode' => 'nullable|string|unique:medicines,barcode',
            'category_id' => 'required|exists:categories,id',
            'manufacturer' => 'nullable|string',
            'unit' => 'nullable|string',
            'description' => 'nullable|string',
            'min_stock_level' => 'integer',
            'is_prescription_required' => 'boolean',
            'is_active' => 'boolean',
        ]);

        $medicine = Medicine::create($validated);

        return response()->json($medicine->load('category'), Response::HTTP_CREATED);
    }

    public function show(Medicine $medicine)
    {
        return $medicine->load(['category', 'inventoryItems.supplier']);
    }

    public function update(Request $request, Medicine $medicine)
    {
        $validated = $request->validate([
            'name' => 'string',
            'generic_name' => 'nullable|string',
            'sku' => 'nullable|string|unique:medicines,sku,' . $medicine->id,
            'barcode' => 'nullable|string|unique:medicines,barcode,' . $medicine->id,
            'category_id' => 'exists:categories,id',
            'manufacturer' => 'nullable|string',
            'unit' => 'nullable|string',
            'description' => 'nullable|string',
            'min_stock_level' => 'integer',
            'is_prescription_required' => 'boolean',
            'is_active' => 'boolean',
        ]);

        $medicine->update($validated);

        return response()->json($medicine->load('category'));
    }

    public function destroy(Medicine $medicine)
    {
        $medicine->delete();

        return response()->json(null, Response::HTTP_NO_CONTENT);
    }
}
