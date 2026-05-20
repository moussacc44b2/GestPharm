<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('medicines', function (Blueprint $table) {
            $table->index('category_id');
        });

        Schema::table('inventory_items', function (Blueprint $table) {
            $table->index('medicine_id');
            $table->index('supplier_id');
            $table->index('barcode');
            $table->index('expiry_date');
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->index('user_id');
            $table->index('created_at');
        });

        Schema::table('sale_items', function (Blueprint $table) {
            $table->index('sale_id');
            $table->index('inventory_item_id');
        });

        Schema::table('purchase_items', function (Blueprint $table) {
            $table->index('purchase_id');
            $table->index('medicine_id');
        });

        Schema::table('inventory_movements', function (Blueprint $table) {
            $table->index('inventory_item_id');
            $table->index('user_id');
            $table->index(['reference_type', 'reference_id']);
        });

        Schema::table('cash_transactions', function (Blueprint $table) {
            $table->index('user_id');
            $table->index(['reference_type', 'reference_id']);
            $table->index('created_at');
        });

        Schema::table('debts', function (Blueprint $table) {
            $table->index('supplier_id');
            $table->index('sale_id');
            $table->index('purchase_id');
        });

        Schema::table('barcode_scans', function (Blueprint $table) {
            $table->index(['user_id', 'processed']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('barcode_scans', function (Blueprint $table) {
            $table->dropIndex(['user_id', 'processed']);
        });

        Schema::table('debts', function (Blueprint $table) {
            $table->dropIndex(['supplier_id']);
            $table->dropIndex(['sale_id']);
            $table->dropIndex(['purchase_id']);
        });

        Schema::table('cash_transactions', function (Blueprint $table) {
            $table->dropIndex(['user_id']);
            $table->dropIndex(['reference_type', 'reference_id']);
            $table->dropIndex(['created_at']);
        });

        Schema::table('inventory_movements', function (Blueprint $table) {
            $table->dropIndex(['inventory_item_id']);
            $table->dropIndex(['user_id']);
            $table->dropIndex(['reference_type', 'reference_id']);
        });

        Schema::table('purchase_items', function (Blueprint $table) {
            $table->dropIndex(['purchase_id']);
            $table->dropIndex(['medicine_id']);
        });

        Schema::table('sale_items', function (Blueprint $table) {
            $table->dropIndex(['sale_id']);
            $table->dropIndex(['inventory_item_id']);
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->dropIndex(['user_id']);
            $table->dropIndex(['created_at']);
        });

        Schema::table('inventory_items', function (Blueprint $table) {
            $table->dropIndex(['medicine_id']);
            $table->dropIndex(['supplier_id']);
            $table->dropIndex(['barcode']);
            $table->dropIndex(['expiry_date']);
        });

        Schema::table('medicines', function (Blueprint $table) {
            $table->dropIndex(['category_id']);
        });
    }
};
