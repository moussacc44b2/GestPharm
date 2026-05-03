<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Medicine extends Model
{
    use HasFactory;

    protected $fillable = [
        'name',
        'generic_name',
        'sku',
        'barcode',
        'category_id',
        'manufacturer',
        'unit',
        'description',
        'min_stock_level',
        'is_prescription_required',
        'is_active',
    ];

    protected $casts = [
        'is_prescription_required' => 'boolean',
        'is_active' => 'boolean',
        'min_stock_level' => 'integer',
    ];

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    public function inventoryItems(): HasMany
    {
        return $this->hasMany(InventoryItem::class);
    }

    public function getTotalStockAttribute(): int
    {
        return $this->inventoryItems()->sum('quantity');
    }
}
