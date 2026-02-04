using GastroApp.Models;

namespace GastroApp.Services;

public class AuthService
{
    private readonly UserService _userService;
    private User? _currentUser;

    public AuthService(UserService userService)
    {
        _userService = userService;
    }

    public User? CurrentUser => _currentUser;
    public bool IsAuthenticated => _currentUser != null;

    public bool Login(string username, string password)
    {
        var user = _userService.GetByUsername(username);
        if (user == null)
            return false;

        if (!BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
            return false;

        _currentUser = user;
        return true;
    }

    public void Logout()
    {
        _currentUser = null;
    }

    public bool IsInRole(UserRole role)
    {
        return _currentUser?.Role == role;
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
