using GastroApp.Models;

namespace GastroApp.Services;

public class UserService
{
    private readonly DataStorageService _storage;

    public UserService(DataStorageService storage)
    {
        _storage = storage;
    }

    public List<User> GetAll() => _storage.Users;

    public User? GetById(int id) => _storage.Users.FirstOrDefault(u => u.Id == id);

    public User? GetByUsername(string username) => _storage.Users.FirstOrDefault(u => u.Username == username);

    public void Add(User user)
    {
        user.Id = _storage.GetNextUserId();
        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(user.PasswordHash);
        _storage.Users.Add(user);
        _storage.SaveToFile();
    }

    public void Update(User user)
    {
        var existing = GetById(user.Id);
        if (existing != null)
        {
            existing.Username = user.Username;
            if (!string.IsNullOrEmpty(user.PasswordHash))
            {
                existing.PasswordHash = BCrypt.Net.BCrypt.HashPassword(user.PasswordHash);
            }
            existing.Role = user.Role;
            _storage.SaveToFile();
        }
    }

    public void Delete(int id)
    {
        var user = GetById(id);
        if (user != null)
        {
            _storage.Users.Remove(user);
            _storage.SaveToFile();
        }
    }
}
