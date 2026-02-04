using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Web;
using GastroApp.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorPages();
builder.Services.AddServerSideBlazor();

// Servicios de la app (Singleton para mantener estado en memoria)
builder.Services.AddSingleton<DataStorageService>();
builder.Services.AddSingleton<ProductService>();
builder.Services.AddSingleton<SaleService>();
builder.Services.AddSingleton<CashRegisterService>();
builder.Services.AddSingleton<UserService>();
builder.Services.AddSingleton<AuthService>();

var app = builder.Build();

// Cargar datos persistidos al iniciar
var storage = app.Services.GetRequiredService<DataStorageService>();
storage.LoadFromFile();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseStaticFiles();

app.UseRouting();

app.MapBlazorHub();
app.MapFallbackToPage("/_Host");

app.Run();
