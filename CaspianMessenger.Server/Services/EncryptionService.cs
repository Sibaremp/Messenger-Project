using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using CaspianMessenger.Server.DTOs.Chat;
using Org.BouncyCastle.Crypto.Agreement;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Security;

namespace CaspianMessenger.Server.Services;

/// <summary>
/// Per-user X25519 ECDH key exchange + AES-256-GCM transport encryption.
///
/// Flow:
///   1. Client calls POST /api/key-exchange → server generates X25519 key pair,
///      computes DH shared secret, derives 256-bit AES key via HKDF-SHA256,
///      stores it under userId, returns server public key to client.
///   2. Client encrypts plaintext → ENC:&lt;nonce_b64&gt;.&lt;(ct‖tag)_b64&gt;
///   3. Server decrypts with Decrypt(), stores plaintext in DB.
///   4. Before sending to any client via REST or SignalR, server re-encrypts
///      with that specific recipient's key using Encrypt().
/// </summary>
public class EncryptionService
{
    private const string EncPrefix = "ENC:";
    private const string HkdfInfo  = "CaspianMessenger-v1";
    private const string HkdfSalt  = "CaspianMessenger-salt-2024";

    // userId → 32-byte AES-256 key (derived from DH shared secret)
    private readonly ConcurrentDictionary<Guid, byte[]> _keys = new();

    // ── Key Exchange ─────────────────────────────────────────────────────────

    /// <summary>
    /// Generates an ephemeral X25519 server key pair, derives a shared AES-256 key
    /// via HKDF-SHA256, stores it under <paramref name="userId"/>, and returns the
    /// server's public key as a Base64 string.
    /// </summary>
    public string PerformKeyExchange(Guid userId, string clientPublicKeyBase64)
    {
        var random = new SecureRandom();
        var gen    = new X25519KeyPairGenerator();
        gen.Init(new X25519KeyGenerationParameters(random));
        var kp = gen.GenerateKeyPair();

        var clientPubBytes = Convert.FromBase64String(clientPublicKeyBase64);
        var clientPub      = new X25519PublicKeyParameters(clientPubBytes);

        var agreement    = new X25519Agreement();
        agreement.Init(kp.Private);
        var rawShared    = new byte[agreement.AgreementSize]; // 32 bytes
        agreement.CalculateAgreement(clientPub, rawShared, 0);

        // HKDF-SHA256 (built-in .NET 5+): Extract + Expand
        var salt   = Encoding.UTF8.GetBytes(HkdfSalt);
        var info   = Encoding.UTF8.GetBytes(HkdfInfo);
        var prk    = HKDF.Extract(HashAlgorithmName.SHA256, rawShared, salt);
        var aesKey = HKDF.Expand(HashAlgorithmName.SHA256, prk, 32, info);

        _keys[userId] = aesKey;

        var serverPubBytes = ((X25519PublicKeyParameters)kp.Public).GetEncoded();
        return Convert.ToBase64String(serverPubBytes);
    }

    /// <summary>
    /// Returns <c>true</c> if an active shared key exists for <paramref name="userId"/>.
    /// </summary>
    public bool HasKey(Guid userId) => _keys.ContainsKey(userId);

    /// <summary>Removes the key for <paramref name="userId"/> (on logout / reconnect).</summary>
    public void ClearKey(Guid userId) => _keys.TryRemove(userId, out _);

    // ── Encrypt / Decrypt ────────────────────────────────────────────────────

    /// <summary>
    /// Encrypts <paramref name="text"/> for <paramref name="userId"/> with AES-256-GCM.
    /// Returns <c>ENC:&lt;nonce_b64&gt;.&lt;(ct‖tag)_b64&gt;</c>, or the original text
    /// if no key is registered or the text is empty/already encrypted.
    /// </summary>
    public string Encrypt(Guid userId, string text)
    {
        if (string.IsNullOrEmpty(text) || text.StartsWith(EncPrefix))
            return text;
        if (!_keys.TryGetValue(userId, out var key))
            return text;

        try
        {
            var nonce = RandomNumberGenerator.GetBytes(12);
            using var aes = new AesGcm(key, tagSizeInBytes: 16);

            var plain   = Encoding.UTF8.GetBytes(text);
            var ct      = new byte[plain.Length];
            var tag     = new byte[16];
            aes.Encrypt(nonce, plain, ct, tag);

            // payload = ciphertext ‖ GCM tag
            var payload = new byte[ct.Length + 16];
            ct.CopyTo(payload, 0);
            tag.CopyTo(payload, ct.Length);

            return $"{EncPrefix}{Convert.ToBase64String(nonce)}.{Convert.ToBase64String(payload)}";
        }
        catch
        {
            return text; // graceful degradation
        }
    }

    /// <summary>
    /// Decrypts a ciphertext produced by <see cref="Encrypt"/>.
    /// If the text does not begin with <c>ENC:</c>, or decryption fails, returns
    /// the original text (graceful degradation — works even if key was never set).
    /// </summary>
    public string Decrypt(Guid userId, string text)
    {
        if (string.IsNullOrEmpty(text) || !text.StartsWith(EncPrefix))
            return text;
        if (!_keys.TryGetValue(userId, out var key))
            return text;

        try
        {
            var body = text[EncPrefix.Length..];
            var dot  = body.IndexOf('.');
            if (dot < 0) return text;

            var nonce   = Convert.FromBase64String(body[..dot]);
            var payload = Convert.FromBase64String(body[(dot + 1)..]);
            if (payload.Length < 16) return text;

            var ct  = payload[..^16];
            var tag = payload[^16..];

            using var aes  = new AesGcm(key, tagSizeInBytes: 16);
            var plain = new byte[ct.Length];
            aes.Decrypt(nonce, ct, tag, plain);
            return Encoding.UTF8.GetString(plain);
        }
        catch
        {
            return text;
        }
    }

    // ── DTO Helpers ───────────────────────────────────────────────────────────

    /// <summary>
    /// Encrypts all message and comment texts inside <paramref name="chat"/> in-place
    /// for <paramref name="userId"/>. Call this just before returning a ChatDto over REST.
    /// </summary>
    public void EncryptChatInPlace(ChatDto chat, Guid userId)
    {
        foreach (var msg in chat.Messages)
        {
            msg.Text = Encrypt(userId, msg.Text);
            if (msg.ReplyTo != null)
                msg.ReplyTo.Text = Encrypt(userId, msg.ReplyTo.Text);
            foreach (var comment in msg.Comments)
                comment.Text = Encrypt(userId, comment.Text);
        }
    }

    /// <summary>Convenience overload for a list of chats (e.g. GET /api/chats).</summary>
    public void EncryptChatsInPlace(IEnumerable<ChatDto> chats, Guid userId)
    {
        foreach (var chat in chats)
            EncryptChatInPlace(chat, userId);
    }
}
