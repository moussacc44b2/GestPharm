<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Role;
use Spatie\Permission\Models\Permission;
use App\Models\User;
use Illuminate\Support\Facades\Hash;

class RolesAndPermissionsSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        // Reset cached roles and permissions
        app()[\Spatie\Permission\PermissionRegistrar::class]->forgetCachedPermissions();

        // create permissions (can add more later)
        Permission::firstOrCreate(['name' => 'manage users']);
        Permission::firstOrCreate(['name' => 'manage inventory']);
        Permission::firstOrCreate(['name' => 'manage sales']);
        Permission::firstOrCreate(['name' => 'manage settings']);
        Permission::firstOrCreate(['name' => 'view reports']);

        // create roles and assign created permissions
        $roleCashier = Role::firstOrCreate(['name' => 'cashier']);
        $roleCashier->givePermissionTo(['manage sales']);

        $rolePharmacist = Role::firstOrCreate(['name' => 'pharmacist']);
        $rolePharmacist->givePermissionTo(['manage inventory', 'manage sales', 'view reports']);

        $roleAdmin = Role::firstOrCreate(['name' => 'admin']);
        $roleAdmin->givePermissionTo(Permission::all());

        // create demo users
        $admin = User::firstOrCreate(
            ['email' => 'admin@gestpharm.com'],
            [
                'name' => 'System Administrator',
                'password' => Hash::make('password'),
            ]
        );
        $admin->assignRole($roleAdmin);
    }
}
