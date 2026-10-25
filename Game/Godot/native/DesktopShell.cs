using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Only controls the explicitly registered windows belonging to the pet process.
// No Explorer injection, global hooks, desktop parenting or user settings changes.
internal static class DesktopShell
{
    internal const long ToolWindow=0x80, AppWindow=0x40000, MinimizeBox=0x20000, MaximizeBox=0x10000;
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] internal static extern IntPtr GetLong(IntPtr h,int n);
    [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetLong(IntPtr h,int n,IntPtr v);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] internal static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(IntPtr h,int cmd);
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h,uint direction);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder name,int count);
    [ComImport,Guid("56FDF344-FD6D-11D0-958A-006097C9A090"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList { void HrInit(); void AddTab(IntPtr h); void DeleteTab(IntPtr h); void ActivateTab(IntPtr h); void SetActiveAlt(IntPtr h); }
    [ComImport,Guid("56FDF342-FD6D-11D0-958A-006097C9A090")] class TaskbarList { }
    static ITaskbarList taskbar;
    static readonly HashSet<IntPtr> registered=new HashSet<IntPtr>();

    internal static bool Maintain(IntPtr h,int owner,bool desktopFront)
    {
        uint pid; GetWindowThreadProcessId(h,out pid);
        if(h==IntPtr.Zero || pid!=(uint)owner) return false;
        long ex=GetLong(h,-20).ToInt64(), style=GetLong(h,-16).ToInt64();
        long wantedEx=(ex|ToolWindow)&~AppWindow, wantedStyle=style&~(MinimizeBox|MaximizeBox);
        bool changed=ex!=wantedEx || style!=wantedStyle;
        if(changed) {
            SetLong(h,-20,new IntPtr(wantedEx)); SetLong(h,-16,new IntPtr(wantedStyle));
            SetWindowPos(h,IntPtr.Zero,0,0,0,0,0x37); // Frame changed, no size/position/z/focus changes.
        }
        if(changed || registered.Add(h)) {
            try {
                if(taskbar==null) { taskbar=(ITaskbarList)new TaskbarList(); taskbar.HrInit(); }
                taskbar.DeleteTab(h);
            } catch(COMException) { taskbar=null; }
        }
        // A hidden cauldron stays hidden. Show Desktop may minimize a visible widget;
        // restoring without activation never steals keyboard input from another app.
        if(IsWindowVisible(h) && IsIconic(h)) ShowWindow(h,4);
        if(desktopFront && IsWindowVisible(h) && DesktopAbove(h))
            SetWindowPos(h,(wantedEx&8)!=0 ? new IntPtr(-1) : IntPtr.Zero,0,0,0,0,0x13);
        return true;
    }

    static bool DesktopInFront()
    {
        var name=new StringBuilder(256); GetClassName(GetForegroundWindow(),name,name.Capacity);
        return name.ToString()=="Progman" || name.ToString()=="WorkerW" || name.ToString()=="Shell_TrayWnd";
    }

    static bool DesktopAbove(IntPtr h)
    {
        // Keep the existing pet/cauldron/food stacking order during normal use.
        // Only raise a widget if Show Desktop really put a visible desktop above it.
        for(int i=0;i<1024;i++) {
            h=GetWindow(h,3); if(h==IntPtr.Zero) break;
            var name=new StringBuilder(256); GetClassName(h,name,name.Capacity);
            if(IsWindowVisible(h) && (name.ToString()=="Progman" || name.ToString()=="WorkerW")) return true;
        }
        return false;
    }

    static int ZRank(IntPtr h)
    {
        int rank=0;
        while(rank<1024 && (h=GetWindow(h,3))!=IntPtr.Zero) rank++;
        return rank;
    }

    [STAThread] static int Main(string[] args)
    {
        int owner;
        if(args.Length!=2 || !int.TryParse(args[0],out owner)) return 2;
        string request=Path.GetFullPath(args[1]);
        try {
            using(var parent=Process.GetProcessById(owner)) {
                var handles=new List<IntPtr>(); string previous="";
                while(!parent.HasExited) {
                    try {
                        string text=File.ReadAllText(request);
                        if(text!=previous) {
                            var next=new List<IntPtr>();
                            foreach(var line in text.Split('\n')) { long value; if(long.TryParse(line.Trim(),out value)) next.Add(new IntPtr(value)); }
                            handles=next; previous=text;
                        }
                    } catch(IOException) { }
                    bool desktop=DesktopInFront();
                    if(desktop) handles.Sort((a,b)=>ZRank(b).CompareTo(ZRank(a)));
                    foreach(var handle in handles) Maintain(handle,owner,desktop);
                    Thread.Sleep(150);
                }
            }
        } catch(ArgumentException) { } catch(InvalidOperationException) { }
        finally { if(taskbar!=null) Marshal.ReleaseComObject(taskbar); }
        return 0;
    }
}
