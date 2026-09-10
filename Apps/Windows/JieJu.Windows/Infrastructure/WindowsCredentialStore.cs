using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace JieJu.Windows.Infrastructure;

public interface IAPIKeyStore
{
    string Load();
    void Save(string value);
}

public sealed class WindowsCredentialStore : IAPIKeyStore
{
    private const string DefaultTarget = "JieJu/OpenAICompatible/APIKey";
    private const uint Generic = 1;
    private const uint LocalMachine = 2;
    private const int NotFound = 1168;
    private readonly string target;

    public WindowsCredentialStore(string target = DefaultTarget) => this.target = target;

    public string Load()
    {
        if (!CredRead(target, Generic, 0, out var pointer)) return "";
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0) return "";
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.UTF8.GetString(bytes);
        }
        finally { CredFree(pointer); }
    }

    public void Save(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            if (!CredDelete(target, Generic, 0) && Marshal.GetLastWin32Error() != NotFound) throw new Win32Exception(Marshal.GetLastWin32Error());
            return;
        }
        var bytes = Encoding.UTF8.GetBytes(trimmed);
        if (bytes.Length > 2560) throw new ArgumentException("API Key 超过 Windows 凭据管理器支持的长度。", nameof(value));
        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new Credential
            {
                Type = Generic, TargetName = target, CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob, Persist = LocalMachine, UserName = Environment.UserName
            };
            if (!CredWrite(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally { Marshal.FreeCoTaskMem(blob); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags, Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes, TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr credential);
}
