using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32.SafeHandles;

partial class BowlFiles {
    [DllImport("kernel32.dll",SetLastError=true)]
    static extern bool SetFileInformationByHandle(SafeFileHandle file,int kind,IntPtr data,uint size);
    static FileStream MutationHandle(string path) {
        // No write/delete sharing: operate on the exact verified file handle,
        // preventing a path replacement between identity check and mutation.
        return new FileStream(path,FileMode.Open,FileSystemRights.Read|FileSystemRights.Delete,FileShare.Read,4096,FileOptions.None);
    }
    static void DeleteHandle(FileStream file) {
        IntPtr data=Marshal.AllocHGlobal(4);
        try {
            Marshal.WriteInt32(data,1);
            if(!SetFileInformationByHandle(file.SafeFileHandle,4,data,4)) throw new IOException("文件暂时无法消化",new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()));
        } finally { Marshal.FreeHGlobal(data); }
    }
    static void MoveHandle(FileStream file,string target) {
        byte[] name=Encoding.Unicode.GetBytes(Path.GetFullPath(target));
        int rootOffset=IntPtr.Size, lengthOffset=rootOffset+IntPtr.Size, nameOffset=lengthOffset+4;
        int size=nameOffset+name.Length+2;
        IntPtr data=Marshal.AllocHGlobal(size);
        try {
            Marshal.Copy(new byte[size],0,data,size); // ReplaceIfExists=false.
            Marshal.WriteInt32(data,lengthOffset,name.Length);
            Marshal.Copy(name,0,IntPtr.Add(data,nameOffset),name.Length);
            if(!SetFileInformationByHandle(file.SafeFileHandle,3,data,(uint)size)) throw new IOException("文件暂时无法移动",new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()));
        } finally { Marshal.FreeHGlobal(data); }
    }
    public class Arrival { public string token; public long entered; public long order; }
    public class GutEntry { public string token; public long entered; }
    static string stomach;
    static long stomachCapacity;
    static double digestionHours;
    static readonly DateTime Epoch=new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc);
    static long Now() { return (long)(DateTime.UtcNow-Epoch).TotalMilliseconds; }
    static void ConfigureDigestion(Dictionary<string,object> job) {
        stomach=Path.Combine(Path.GetDirectoryName(root),"猫的胃袋");
        stomachCapacity=job.ContainsKey("stomach_capacity")?Convert.ToInt64(job["stomach_capacity"]):1073741824L;
        stomachCapacity=Math.Max(1048576L,Math.Min(1099511627776L,stomachCapacity));
        digestionHours=job.ContainsKey("digestion_hours")?Convert.ToDouble(job["digestion_hours"]):6.0;
        if(Double.IsNaN(digestionHours)||Double.IsInfinity(digestionHours)) digestionHours=6.0;
        digestionHours=Math.Max(0.01,Math.Min(8760.0,digestionHours));
    }
    static void EnsureStomach() { Guard(stomach,false); Directory.CreateDirectory(stomach); }
    static Dictionary<string,T> ReadLedger<T>(string path) {
        Guard(path,false);
        if(!File.Exists(path)) return new Dictionary<string,T>(StringComparer.OrdinalIgnoreCase);
        var data=json.Deserialize<Dictionary<string,T>>(File.ReadAllText(path,Encoding.UTF8));
        if(data==null) throw new IOException("文件时间记录无法读取，已暂停处理");
        return new Dictionary<string,T>(data,StringComparer.OrdinalIgnoreCase);
    }
    static void SaveLedger<T>(string path,Dictionary<string,T> data) {
        Guard(path,false);
        string temp=Path.Combine(Path.GetDirectoryName(path),".pet-ledger-"+Guid.NewGuid().ToString("N")+".tmp");
        byte[] bytes=new UTF8Encoding(false).GetBytes(json.Serialize(data));
        using(var stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { stream.Write(bytes,0,bytes.Length); stream.Flush(true); }
        if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
        File.SetAttributes(path,FileAttributes.Hidden);
    }
    static string Relative(string folder,string path) {
        string prefix=Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        string full=Path.GetFullPath(path);
        if(!full.StartsWith(prefix,StringComparison.OrdinalIgnoreCase)) throw new IOException("文件不在目标目录中");
        return full.Substring(prefix.Length);
    }
    static void RecordArrival(string path) {
        string ledger=Path.Combine(root,".bowl-state.json");
        var entries=ReadLedger<Arrival>(ledger);
        long next=entries.Count==0?1:entries.Values.Max(e=>e.order)+1;
        using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
            entries[Relative(root,path)]=new Arrival { token=Token(stream),entered=Now(),order=next };
        }
        SaveLedger(ledger,entries);
    }
    static long ScanStomach(List<string> errors) {
        EnsureStomach(); long now=Now(),total=0;
        string ledger=Path.Combine(stomach,".stomach-state.json");
        var records=ReadLedger<GutEntry>(ledger);
        var files=new List<string>(); Walk(stomach,files,errors);
        bool changed=false;
        var present=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string path in files) {
            string key=Relative(stomach,path); present.Add(key);
            try {
                Guard(path,false);
                using(var handle=MutationHandle(path)) {
                    string token=Token(handle); GutEntry entry;
                    if(!records.TryGetValue(key,out entry)||entry==null||entry.token!=token||entry.entered<=0) {
                        // Manually added/replaced files start their own clock. Never
                        // infer deletion eligibility from creation/modified time.
                        entry=new GutEntry {token=token,entered=now}; records[key]=entry; changed=true;
                    }
                    if(now-entry.entered>=digestionHours*3600000.0) {
                        // Only this enumerated, identity-checked regular file can
                        // be deleted. There is no recursive directory deletion.
                        DeleteHandle(handle); records.Remove(key); changed=true;
                    } else total=checked(total+handle.Length);
                }
            } catch(IOException e) { if(File.Exists(path)) total=checked(total+new FileInfo(path).Length); errors.Add(e.Message); }
              catch(UnauthorizedAccessException e) { if(File.Exists(path)) total=checked(total+new FileInfo(path).Length); errors.Add(e.Message); }
        }
        if(errors.Count==0) foreach(string key in records.Keys.ToArray()) if(!present.Contains(key)) { records.Remove(key); changed=true; }
        if(changed||!File.Exists(ledger)) SaveLedger(ledger,records);
        return total;
    }
    static object ScanQueued() {
        var errors=new List<string>(); long gutBytes=ScanStomach(errors);
        var files=new List<string>(); Walk(root,files,errors);
        bool sizesComplete=errors.Count==0; long smallestBytes=-1;
        string ledger=Path.Combine(root,".bowl-state.json"); bool initial=!File.Exists(ledger);
        var records=ReadLedger<Arrival>(ledger);
        long next=records.Count==0?1:records.Values.Max(e=>e.order)+1;
        // At migration there is no recorded arrival history. Stable creation
        // order is a fallback; subsequent arrivals get monotonic queue numbers.
        files=files.OrderBy(p=>File.GetCreationTimeUtc(p)).ThenBy(p=>p,StringComparer.OrdinalIgnoreCase).ToList();
        var rows=new List<Dictionary<string,object>>(); long total=0; bool changed=false;
        var present=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string path in files) {
            string key=Relative(root,path); present.Add(key);
            var info=new FileInfo(path); long length;
            try { Guard(path,true); length=info.Length; }
            catch(IOException e) { sizesComplete=false; errors.Add(e.Message); continue; }
            catch(UnauthorizedAccessException e) { sizesComplete=false; errors.Add(e.Message); continue; }
            if(smallestBytes<0||length<smallestBytes) smallestBytes=length;
            total=checked(total+length); bool ready=false; string token="";
            try {
                Guard(path,true);
                using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) token=Token(stream);
                ready=(DateTime.UtcNow-info.LastWriteTimeUtc).TotalSeconds>=1.5;
            } catch(IOException) {} catch(UnauthorizedAccessException) {}
            Arrival entry;
            if(!records.TryGetValue(key,out entry)||entry==null||(!String.IsNullOrEmpty(token)&&!String.IsNullOrEmpty(entry.token)&&token!=entry.token)) {
                entry=new Arrival {token=token,entered=initial?Math.Min(Now(),(long)(info.CreationTimeUtc-Epoch).TotalMilliseconds):Now(),order=next++};
                records[key]=entry; changed=true;
            } else if(String.IsNullOrEmpty(entry.token)&&!String.IsNullOrEmpty(token)) { entry.token=token; changed=true; }
            rows.Add(new Dictionary<string,object> {{"path",path},{"token",token},{"bytes",length},{"icon",""},{"label",Path.GetFileName(path)},{"ready",ready},{"entered",entry.entered},{"order",entry.order}});
        }
        if(errors.Count==0) foreach(string key in records.Keys.ToArray()) if(!present.Contains(key)) { records.Remove(key); changed=true; }
        if(changed||!File.Exists(ledger)) SaveLedger(ledger,records);
        rows=rows.OrderBy(e=>(long)e["order"]).Take(128).ToList();
        foreach(var row in rows) if((bool)row["ready"]) {
            string path=(string)row["path"],icon=Path.Combine(cache,Hash(path+(string)row["token"])+".png");
            try { if(!File.Exists(icon)) SaveIcon(path,icon); row["icon"]=icon; }
            catch(Exception) {} // An icon failure uses the app's generic icon, not a FIFO bypass.
        }
        // The visible queue is capped at 128 entries, but this proof covers every
        // enumerated food file. An incomplete scan must never permit overflow.
        return new {ok=true,bytes=total,entries=rows,smallest_bytes=sizesComplete&&errors.Count==0?smallestBytes:-1,stomach_bytes=gutBytes,errors=errors};
    }
    static bool AllQueuedFoodExceedsCapacity(string heldPath,long heldBytes) {
        var errors=new List<string>(); var files=new List<string>(); Walk(root,files,errors);
        if(errors.Count!=0||files.Count==0) return false;
        bool foundHeld=false;
        foreach(string path in files) {
            try {
                Guard(path,true);
                if(String.Equals(Path.GetFullPath(path),Path.GetFullPath(heldPath),StringComparison.OrdinalIgnoreCase)) {
                    foundHeld=true;
                    if(heldBytes<=stomachCapacity) return false;
                } else using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                    Token(stream); // Reject a link or replacement while checking.
                    if(stream.Length<=stomachCapacity) return false;
                }
            } catch(IOException) { return false; }
              catch(UnauthorizedAccessException) { return false; }
        }
        return foundHeld;
    }
    static object Swallow(string path,string expected) {
        Guard(path,true); if(Metadata(path)) throw new IOException("配置文件不可投喂");
        var errors=new List<string>(); long used=ScanStomach(errors);
        string ledger=Path.Combine(stomach,".stomach-state.json");
        var records=ReadLedger<GutEntry>(ledger);
        using(var handle=MutationHandle(path)) {
            if(Token(handle)!=expected) throw new IOException("文件已修改，保留文件并重新排队");
            if(handle.Length>stomachCapacity-used) {
                // One whole oversized file can end a hungry meal when every
                // food exceeds the configured capacity. Recheck live files in
                // the worker's existing mutex; never trust a UI permission flag.
                bool oversized=handle.Length>stomachCapacity&&used<stomachCapacity&&used*2<stomachCapacity
                    &&errors.Count==0&&AllQueuedFoodExceedsCapacity(path,handle.Length);
                if(!oversized) throw new IOException("胃袋装不下这份食物，已留在饭盆");
            }
            string name=Path.GetFileName(path),target=Path.Combine(stomach,name); int suffix=2;
            while(File.Exists(target)||Directory.Exists(target)) target=Path.Combine(stomach,Path.GetFileNameWithoutExtension(name)+" ("+(suffix++)+")"+Path.GetExtension(name));
            Guard(target,false); string key=Relative(stomach,target);
            // Write the destination identity/time BEFORE the atomic same-volume
            // move: a crash on either side leaves the food recoverable and timed.
            records[key]=new GutEntry {token=Token(handle,target),entered=Now()};
            SaveLedger(ledger,records);
            MoveHandle(handle,target);
            return new {ok=true,path=path,token=expected,target=target,stomach_bytes=checked(used+handle.Length)};
        }
    }
}
