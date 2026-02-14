# GastroApp – Food Business Management System (Prototype)

Functional prototype of a web-based management system designed for small food businesses.
Built with Blazor Server and C#, focused on structured architecture and clear business logic separation.

## Tech Stack

- **C# / ASP.NET Core 7.0**
- **Blazor Server**
- **In-memory data storage** (no database integration yet)

## Project Structure

```
GastroApp/
├── Models/                 # Domain models
│   ├── Product.cs
│   ├── Sale.cs
│   ├── CashRegister.cs
│   └── DailySummary.cs
├── Services/               # Business logic layer
│   ├── DataStorageService.cs
│   ├── ProductService.cs
│   ├── SaleService.cs
│   └── CashRegisterService.cs
└── Pages/                  # Blazor pages (UI layer)
    ├── Index.razor
    ├── Products.razor
    ├── Sales.razor
    ├── Cash.razor
    └── Summary.razor
```

## Features

### Product Management

Create, edit, and list products

Fields: Name, Price, Optional Cost

Visual margin indicator:

🟢 Healthy margin (30%+)

🟠 Low margin (0–30%)

🔴 Negative margin

### Point of Sale (POS)

Counter-style interface

Click products to add to cart

Real-time total calculation

“Checkout” button to register sale

Requires an open cash register

### Daily Cash Register

Open register with initial amount

Track daily sales in real time

Close register with final counted amount

Automatic difference calculation

One register session per day

### Daily Summary

Total sales amount

Number of transactions

Best-selling product

Cash register status and difference

## How to Run

```bash
cd GastroApp
dotnet run
```

The application will be available at:

To stop the application, press Ctrl + C.

## Recommended Usage Flow

Open Cash Register

Create Products

Register Sales

Close Cash Register

Review Daily Summary

## Technical Notes

Data persistence is currently in-memory. Restarting the application resets all data.

Includes preloaded sample products for testing.

No authentication system implemented.

Intended for local development and architecture validation.

## Potential Improvements  

Database integration (SQL / EF Core)

Persistent storage (JSON or database)

Historical sales tracking

Date-range reporting

Product categories

Ticket printing

Stock management

---