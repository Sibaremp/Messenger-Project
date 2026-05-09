using System.Security.Cryptography;
using System.Text;
namespace CaspianMessenger.Server.Helpers;

public static class TokenHashHelper
{
    public static string ComputeSha256(string token)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
