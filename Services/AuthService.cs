using GastroApp.Models;

namespace GastroApp.Services;

public class AuthService
{
    private readonly UserService _userService;
    private int? _currentUserId;
    private string? _loginUsername;
    private string? _loginPasswordHash;

    public event Action? OnAuthStateChanged;

    public AuthService(UserService userService)
    {
        _userService = userService;
    }

    public User? CurrentUser
    {
        get
        {
            if (!_currentUserId.HasValue) return null;
            var user = _userService.GetById(_currentUserId.Value);
            if (user == null || user.Id <= 0 || string.IsNullOrWhiteSpace(user.Username)
                || user.Username != _loginUsername || user.PasswordHash != _loginPasswordHash)
            {
                // Lazy invalidation must not notify/re-enter components during rendering.
                ClearIdentity();
                return null;
            }
            return user;
        }
    }
    public bool IsAuthenticated => CurrentUser != null;

    public bool Login(string username, string password)
    {
        var user = _userService.GetByUsername(username);
        if (user == null || user.Id <= 0 || string.IsNullOrWhiteSpace(user.Username))
            return false;

        if (!BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
            return false;

        _currentUserId = user.Id;
        _loginUsername = user.Username;
        _loginPasswordHash = user.PasswordHash;
        OnAuthStateChanged?.Invoke();
        return true;
    }

    public void Logout()
    {
        ClearIdentity();
        OnAuthStateChanged?.Invoke();
    }

    private void ClearIdentity()
    {
        _currentUserId = null;
        _loginUsername = null;
        _loginPasswordHash = null;
    }

    public bool IsInRole(UserRole role)
    {
        return CurrentUser?.Role == role;
    }

    public void RequireAuth()
    {
        if (!IsAuthenticated)
            throw new UnauthorizedAccessException("Usuario no autenticado");
    }

    public void RequireRole(UserRole role)
    {
        RequireAuth();
        if (!IsInRole(role))
            throw new UnauthorizedAccessException($"Se requiere el rol {role}");
    }
}
