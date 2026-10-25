// Windows file operations run outside the animation thread. JSON in/out, no shell commands.
using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using Microsoft.Win32.SafeHandles;

partial class BowlFiles {
    static JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 16777216 };
    static string root, cache;
    [STAThread] static int Main(string[] args) {
        if (args.Length != 2) return 2;
        object result;
        try {
            var job = json.Deserialize<Dictionary<string,object>>(File.ReadAllText(args[0], Encoding.UTF8));
            root = Path.GetFullPath((string)job["root"]).TrimEnd(Path.DirectorySeparatorChar);
            cache = Path.GetFullPath((string)job["cache"]);
            Guard(root, false);
            Directory.CreateDirectory(root); Directory.CreateDirectory(cache);
            ConfigureDigestion(job);
            using (var mutex = new System.Threading.Mutex(false,"Local\\DolikeBowl-"+Hash(root.ToUpperInvariant()))) {
            bool owned=false;
            try {
            try { owned=mutex.WaitOne(10000); } catch(System.Threading.AbandonedMutexException) { owned=true; }
            if(!owned) throw new IOException("饭盆正在处理文件，请稍后再试");
            string action = (string)job["action"];
            if (action == "ensure") { Setup((string)job["art"]); EnsureStomach(); result = new { ok = true }; }
            else if (action == "scan") result = ScanQueued();
            else if (action == "import") result = Import((System.Collections.IEnumerable)job["paths"]);
            else if (action == "swallow") result = Swallow((string)job["path"], (string)job["token"]);
            else throw new IOException("Unknown action");
            } finally { if(owned) mutex.ReleaseMutex(); }
            }
        } catch (Exception e) { result = new { ok = false, error = e.Message }; }
        string temp = args[1]+".tmp";
        File.WriteAllText(temp, json.Serialize(result), new UTF8Encoding(false));
        File.Move(temp, args[1]);
        return 0;
    }
    static void Guard(string path, bool inside) {
        string full = Path.GetFullPath(path);
        if (inside && !full.StartsWith(root+Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new IOException("文件已离开饭盆");
        for (string p = full; !String.IsNullOrEmpty(p); p = Path.GetDirectoryName(p)) {
            if ((File.Exists(p)||Directory.Exists(p)) && (File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
                throw new IOException("饭盆不处理链接目录或符号链接");
        }
    }
    static bool Metadata(string p) {
        string n=Path.GetFileName(p);
        return n.Equals("desktop.ini",StringComparison.OrdinalIgnoreCase) || n.Equals(".bowl.ico",StringComparison.OrdinalIgnoreCase)
            || n.StartsWith(".bowl-import-",StringComparison.OrdinalIgnoreCase)
            || n.StartsWith(".pet-ledger-",StringComparison.OrdinalIgnoreCase)
            || n.Equals(".bowl-state.json",StringComparison.OrdinalIgnoreCase)
            || n.Equals(".stomach-state.json",StringComparison.OrdinalIgnoreCase);
    }
    static string Hash(string value) {
        using (var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", "").ToLowerInvariant();
    }
    [StructLayout(LayoutKind.Sequential)] struct Info {
        public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME created, accessed, written;
        public uint volume, sizeHigh, sizeLow, links, indexHigh, indexLow;
    }
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info info);
    static string Token(FileStream stream, string renamedPath=null) {
        Info i; if (!GetFileInformationByHandle(stream.SafeFileHandle,out i)) throw new IOException("无法识别文件");
        if ((i.attributes & (uint)FileAttributes.ReparsePoint)!=0) throw new IOException("链接文件不可投喂");
        return Hash(Path.GetFullPath(renamedPath ?? stream.Name).ToUpperInvariant()+String.Join(":",new uint[]{i.volume,i.indexHigh,i.indexLow,i.sizeHigh,i.sizeLow,(uint)i.written.dwHighDateTime,(uint)i.written.dwLowDateTime}));
    }
    static void Walk(string folder, List<string> files, List<string> errors) {
        try {
            Guard(folder,false);
            foreach(string p in Directory.GetFiles(folder)) if(!Metadata(p) && (File.GetAttributes(p)&(FileAttributes.ReparsePoint|FileAttributes.System))==0) files.Add(p);
            foreach(string p in Directory.GetDirectories(folder)) if((File.GetAttributes(p)&(FileAttributes.ReparsePoint|FileAttributes.System))==0) Walk(p,files,errors);
        } catch(Exception e) { errors.Add(e.Message); }
    }
    static object Import(System.Collections.IEnumerable paths) {
        var accepted=new List<string>(); var errors=new List<string>();
        foreach(object value in paths) {
            string p=Path.GetFullPath((string)value);
            try {
                Guard(p,false);
                if(!File.Exists(p)) throw new IOException("请投喂文件；文件夹可双击饭盆后放入");
                if(p.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)) continue;
                string name=Path.GetFileName(p);
                if(Metadata(name)) throw new IOException("这是文件夹配置文件");
                string target=Path.Combine(root,name); int n=2;
                while(File.Exists(target)||Directory.Exists(target)) target=Path.Combine(root,Path.GetFileNameWithoutExtension(name)+" ("+(n++)+")"+Path.GetExtension(name));
                if(String.Equals(Path.GetPathRoot(p),Path.GetPathRoot(root),StringComparison.OrdinalIgnoreCase)) {
                    using(var handle=MutationHandle(p)) { Token(handle); MoveHandle(handle,target); }
                } else {
                    string temp=Path.Combine(root,".bowl-import-"+Guid.NewGuid().ToString("N")+".partial");
                    // Keep the source locked against edits until a flushed destination exists.
                    using(var input=MutationHandle(p)) {
                        Token(input);
                        using(var output=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { input.CopyTo(output); output.Flush(true); }
                        File.Move(temp,target);
                        DeleteHandle(input);
                    }
                }
                accepted.Add(target);
                RecordArrival(target);
            } catch(Exception e) { errors.Add(Path.GetFileName(p)+"："+e.Message); }
        }
        return new { ok=true, accepted=accepted, errors=errors };
    }
    static void Setup(string art) {
        string ico=Path.Combine(root,".bowl.ico"), ini=Path.Combine(root,"desktop.ini");
        if(!File.Exists(ico)) {
            using(var source=Image.FromFile(art)) using(var bitmap=new Bitmap(256,256,PixelFormat.Format32bppArgb)) {
                using(var g=Graphics.FromImage(bitmap)) { g.Clear(Color.Transparent); g.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    float s=Math.Min(256f/source.Width,256f/source.Height); g.DrawImage(source,(256-source.Width*s)/2,(256-source.Height*s)/2,source.Width*s,source.Height*s); }
                using(var png=new MemoryStream()) { bitmap.Save(png,ImageFormat.Png); byte[] data=png.ToArray();
                    using(var w=new BinaryWriter(File.Create(ico))) { w.Write((short)0);w.Write((short)1);w.Write((short)1);w.Write(new byte[]{0,0,0,0});w.Write((short)1);w.Write((short)32);w.Write(data.Length);w.Write(22);w.Write(data); } }
            }
            File.SetAttributes(ico,FileAttributes.Hidden);
        }
        string description="[.ShellClassInfo]\r\nIconResource=.bowl.ico,0\r\nInfoTip=猫的饭盆：吃完移入胃袋，消化到期后永久删除\r\n";
        if(!File.Exists(ini)||File.ReadAllText(ini)!=description) {
            using(var stream=new FileStream(ini,File.Exists(ini)?FileMode.Open:FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {
                stream.SetLength(0);
                using(var writer=new StreamWriter(stream,Encoding.Unicode)) writer.Write(description);
            }
            File.SetAttributes(ini,FileAttributes.Hidden|FileAttributes.System);
        }
        File.SetAttributes(root,File.GetAttributes(root)|FileAttributes.ReadOnly);
        SHChangeNotify(0x08000000,0,IntPtr.Zero,IntPtr.Zero);
    }
    [DllImport("shell32.dll")] static extern void SHChangeNotify(uint id,uint flags,IntPtr a,IntPtr b);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode,PreserveSig=false)] static extern void SHCreateItemFromParsingName(string path,IntPtr bind,ref Guid iid,[MarshalAs(UnmanagedType.Interface)]out IShellItem result);
    static IShellItem ShellItem(string path) { Guid id=typeof(IShellItem).GUID; IShellItem item; SHCreateItemFromParsingName(path,IntPtr.Zero,ref id,out item);return item; }
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
    [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h,int size,out BitmapInfo bitmap);
    [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr dc,IntPtr bitmap,uint start,uint lines,byte[] bits,ref DibHeader info,uint mode);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [StructLayout(LayoutKind.Sequential)] struct BitmapInfo { public int type,width,height,stride; public ushort planes,bits; public IntPtr pixels; }
    [StructLayout(LayoutKind.Sequential)] struct DibHeader { public uint size; public int width,height; public ushort planes,bits; public uint compression,imageSize; public int xppm,yppm; public uint colors,important; }
    static void SaveArgb(IntPtr h,string output) {
        BitmapInfo info; GetObject(h,Marshal.SizeOf(typeof(BitmapInfo)),out info);
        var header=new DibHeader { size=40,width=info.width,height=-Math.Abs(info.height),planes=1,bits=32 };
        var pixels=new byte[info.width*Math.Abs(info.height)*4]; IntPtr dc=GetDC(IntPtr.Zero);
        try { if(GetDIBits(dc,h,0,(uint)Math.Abs(info.height),pixels,ref header,0)==0) throw new IOException("无法读取图标像素"); }
        finally { ReleaseDC(IntPtr.Zero,dc); }
        using(var bitmap=new Bitmap(info.width,Math.Abs(info.height),PixelFormat.Format32bppPArgb)) {
            var data=bitmap.LockBits(new Rectangle(0,0,bitmap.Width,bitmap.Height),ImageLockMode.WriteOnly,PixelFormat.Format32bppPArgb);
            try { Marshal.Copy(pixels,0,data.Scan0,pixels.Length); } finally { bitmap.UnlockBits(data); }
            bitmap.Save(output,ImageFormat.Png);
        }
    }
    [StructLayout(LayoutKind.Sequential)] struct Size { public int x,y; public Size(int x,int y){this.x=x;this.y=y;} }
    static void SaveIcon(string path,string output) {
        IShellItem item=ShellItem(path); IntPtr h=IntPtr.Zero;
        try { ((IShellItemImageFactory)item).GetImage(new Size(256,256),0x4,out h);
            SaveArgb(h,output);
        } catch { using(var icon=Icon.ExtractAssociatedIcon(path)) { if(icon!=null) using(var bmp=icon.ToBitmap()) bmp.Save(output,ImageFormat.Png); } }
        finally { if(h!=IntPtr.Zero)DeleteObject(h); Marshal.ReleaseComObject(item); }
    }
    [ComImport,Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IShellItem {
        void BindToHandler(IntPtr p,ref Guid a,ref Guid b,out IntPtr c); void GetParent(out IShellItem p); void GetDisplayName(uint n,out IntPtr p); void GetAttributes(uint mask,out uint a); void Compare(IShellItem i,uint hint,out int order);
    }
    [ComImport,Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IShellItemImageFactory { void GetImage(Size size,uint flags,out IntPtr bitmap); }
}
