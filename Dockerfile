# Build stage: restore and publish the app with the .NET 10 SDK.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Restore first so the dependency layer is cached between source changes.
COPY GastroApp.csproj ./
RUN dotnet restore GastroApp.csproj

COPY . .
RUN dotnet publish GastroApp.csproj -c Release -o /app/publish --no-restore

# Runtime stage: only the ASP.NET Core runtime and the published output.
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish .

# DataStorageService writes data.json in the working directory,
# so the non-root runtime user must own /app.
RUN chown -R app:app /app
USER app

ENV ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "GastroApp.dll"]
