<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CashTransaction;
use App\Models\Debt;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

class CaisseController extends Controller
{
    public function stats(Request $request)
    {
        $totalInflow = CashTransaction::where('type', 'inflow')->sum('amount');
        $totalOutflow = CashTransaction::where('type', 'outflow')->sum('amount');
        $currentBalance = $totalInflow - $totalOutflow;

        $totalCustomerDebts = Debt::where('type', 'customer')
            ->selectRaw('SUM(total_amount - paid_amount) as outstanding')
            ->value('outstanding') ?? 0;

        $totalSupplierDebts = Debt::where('type', 'supplier')
            ->selectRaw('SUM(total_amount - paid_amount) as outstanding')
            ->value('outstanding') ?? 0;

        // Monthly overview (last 6 months) for chart metrics
        $chartData = [];
        for ($i = 5; $i >= 0; $i--) {
            $monthStart = now()->subMonths($i)->startOfMonth();
            $monthEnd = now()->subMonths($i)->endOfMonth();
            $monthName = $monthStart->format('M Y');

            $inflow = CashTransaction::where('type', 'inflow')
                ->whereBetween('created_at', [$monthStart, $monthEnd])
                ->sum('amount');

            $outflow = CashTransaction::where('type', 'outflow')
                ->whereBetween('created_at', [$monthStart, $monthEnd])
                ->sum('amount');

            $chartData[] = [
                'month' => $monthName,
                'inflow' => (float)$inflow,
                'outflow' => (float)$outflow,
            ];
        }

        return response()->json([
            'current_balance' => (float)$currentBalance,
            'total_inflow' => (float)$totalInflow,
            'total_outflow' => (float)$totalOutflow,
            'total_customer_debts' => (float)$totalCustomerDebts,
            'total_supplier_debts' => (float)$totalSupplierDebts,
            'chart_data' => $chartData,
        ]);
    }

    public function index(Request $request)
    {
        $query = CashTransaction::with('user');

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('category')) {
            $query->where('category', $request->category);
        }

        if ($request->has('start_date') && $request->has('end_date')) {
            $query->whereBetween('created_at', [$request->start_date, $request->end_date]);
        }

        return $query->latest()->paginate($request->get('per_page', 15));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'type' => 'required|in:inflow,outflow',
            'amount' => 'required|numeric|min:0.01',
            'category' => 'required|string', // manual_deposit, manual_withdrawal, expense
            'description' => 'nullable|string',
        ]);

        $transaction = CashTransaction::create([
            'user_id' => $request->user()?->id,
            'type' => $validated['type'],
            'amount' => $validated['amount'],
            'category' => $validated['category'],
            'description' => $validated['description'] ?? 'Manual Cash Entry',
        ]);

        return response()->json($transaction, Response::HTTP_CREATED);
    }

    public function debts(Request $request)
    {
        $query = Debt::with(['sale.items.inventoryItem.medicine', 'purchase.items.medicine', 'supplier']);

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('status')) {
            $query->where('status', $request->status);
        } else {
            $query->where('status', '!=', 'paid');
        }

        return $query->latest()->paginate($request->get('per_page', 15));
    }

    public function payDebt(Request $request, Debt $debt)
    {
        $validated = $request->validate([
            'amount' => 'required|numeric|min:0.01',
        ]);

        return DB::transaction(function () use ($debt, $validated, $request) {
            $debt = Debt::lockForUpdate()->find($debt->id);
            $amountToPay = $validated['amount'];
            $outstanding = $debt->total_amount - $debt->paid_amount;

            if ($amountToPay > $outstanding) {
                return response()->json(['message' => 'Payment exceeds outstanding balance of ' . $outstanding . ' DA'], 422);
            }

            $newPaidAmount = $debt->paid_amount + $amountToPay;
            $status = ($newPaidAmount >= $debt->total_amount) ? 'paid' : 'partially_paid';

            $debt->update([
                'paid_amount' => $newPaidAmount,
                'status' => $status,
            ]);

            // Register corresponding Cash Transaction
            $txType = ($debt->type === 'customer') ? 'inflow' : 'outflow';
            $description = ($debt->type === 'customer')
                ? 'Debt Payment received from customer ' . $debt->customer_name
                : 'Debt Payment made to supplier ' . ($debt->supplier?->name ?? 'Unknown');

            CashTransaction::create([
                'user_id' => $request->user()?->id,
                'type' => $txType,
                'amount' => $amountToPay,
                'category' => 'debt_payment',
                'description' => $description . ' (Ref: #' . $debt->id . ')',
                'reference_type' => Debt::class,
                'reference_id' => $debt->id,
            ]);

            return response()->json([
                'message' => 'Debt payment registered successfully',
                'debt' => $debt->load(['sale', 'purchase', 'supplier']),
            ]);
        });
    }
}
