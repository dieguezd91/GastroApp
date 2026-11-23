using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Routing;

namespace GastroApp.Shared;

/// <summary>
/// NavLink for a sidebar entry that owns several routes (a tabbed view): it is also
/// active on every route prefix listed in <see cref="AlsoMatch"/>.
/// </summary>
public class SectionNavLink : NavLink
{
    [Inject] private NavigationManager Navigation { get; set; } = default!;

    /// <summary>Additional route prefixes, relative to the base URI (e.g. "product-categories").</summary>
    [Parameter] public string[] AlsoMatch { get; set; } = [];

    protected override bool ShouldMatch(string uriAbsolute)
    {
        if (base.ShouldMatch(uriAbsolute)) return true;

        var relative = Navigation.ToBaseRelativePath(uriAbsolute);
        var path = relative.Split('?', '#')[0];
        return AlsoMatch.Any(prefix =>
            path.Equals(prefix, StringComparison.OrdinalIgnoreCase)
            || path.StartsWith(prefix + "/", StringComparison.OrdinalIgnoreCase));
    }
}
