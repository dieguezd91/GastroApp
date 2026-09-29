namespace GastroApp.Models;

public class Product
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public decimal? Cost { get; set; }
    public int? CategoryId { get; set; }
    public bool IsActive { get; set; } = true;

    public decimal Margin
    {
        get
        {
            if (!Cost.HasValue || Cost.Value == 0) return 0;
            return ((Price - Cost.Value) / Price) * 100;
        }
    }

    public string MarginColor
    {
        get
        {
            if (!Cost.HasValue) return "gray";
            var margin = Margin;
            if (margin < 0) return "red";
            if (margin < 30) return "orange";
            return "green";
        }
    }
}
