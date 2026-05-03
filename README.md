# GestPharm - Pharmacy Management System

A modern, robust, and secure Pharmacy Inventory and Sales Management System built with **Next.js**, **Laravel**, and **PostgreSQL**.

## 🚀 Technology Stack
- **Backend**: Laravel 11 (PHP 8.3)
- **Frontend**: Next.js 15+ (TypeScript, Tailwind CSS, Lucide)
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **Infrastucture**: Docker & Docker Compose

## ✨ Key Features
- **Dashboard**: Real-time stats on stock levels, daily sales, and expiry alerts.
- **Medicines Catalog**: Comprehensive management of pharmaceutical products.
- **Inventory Tracking**: Batch-level tracking with expiry date monitoring.
- **POS (Point of Sale)**: Fast and intuitive interface for recording customer sales.
- **Suppliers**: Manage medical distributor relationships.

## 🛠️ Getting Started

### 1. Prerequisites
- Docker & Docker Compose installed on your system.

### 2. Installation & Setup
Clone the repository and run:

```bash
docker compose up --build
```

### 3. Database Migrations
Once the containers are running, execute the migrations:

```bash
docker compose exec backend php artisan migrate
```

### 4. Access the Application
- **Frontend**: [http://localhost:3000](http://localhost:3000)
- **Backend API**: [http://localhost:8000](http://localhost:8000)
- **Mailpit (Email Testing)**: [http://localhost:8025](http://localhost:8025)

## 📁 Project Structure
- `/backend`: Laravel API
- `/frontend`: Next.js Application
- `docker-compose.yml`: Infrastructure configuration
