using System;
using System.Runtime.InteropServices;
class PointerProbe {
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X,Y; }
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int metric);
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int L,T,R,B; }
    [StructLayout(LayoutKind.Sequential)] struct GuiInfo {
        public uint Size,Flags; public IntPtr Active,Focus,Capture,MenuOwner,MoveSize,Caret; public Rect CaretRect;
    }
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GuiInfo info);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,System.Text.StringBuilder text,int count);
    static void Main(string[] args) {
        if(args.Length==1 && args[0]=="primary") {
            Console.WriteLine((GetAsyncKeyState(GetSystemMetrics(23)!=0 ? 2 : 1)&0x8000)!=0 ? "down" : "up");
            return;
        }
        if(args[0]=="capture") {
            uint pid; uint thread=GetWindowThreadProcessId(new IntPtr(long.Parse(args[1])),out pid);
            var info=new GuiInfo();info.Size=(uint)Marshal.SizeOf(info);
            Console.WriteLine(GetGUIThreadInfo(thread,ref info) ? info.Capture.ToInt64().ToString() : "error");
            return;
        }
        if(args[0]=="fixture-press" || args[0]=="fixture-gesture") {
            var h=new IntPtr(long.Parse(args[1]));uint pid;GetWindowThreadProcessId(h,out pid);
            var title=new System.Text.StringBuilder(256);GetWindowText(h,title,title.Capacity);
            if(pid!=uint.Parse(args[2]) || !title.ToString().StartsWith("Dolike drag release fixture"))throw new Exception("Not the isolated test window: "+pid+" "+title);
            bool posted=PostMessage(h,0x201,new IntPtr(1),new IntPtr((210<<16)|210));
            if(args[0]=="fixture-gesture") {
                posted &= PostMessage(h,0x200,new IntPtr(1),new IntPtr((210<<16)|245));
                posted &= PostMessage(h,0x202,IntPtr.Zero,new IntPtr((210<<16)|245));
            }
            Console.WriteLine(posted ? "posted" : "error");
            return;
        }
        var point=new Point { X=int.Parse(args[1]), Y=int.Parse(args[2]) };
        Console.WriteLine(WindowFromPoint(point).ToInt64()==long.Parse(args[0]) ? "hit" : "pass");
    }
}
