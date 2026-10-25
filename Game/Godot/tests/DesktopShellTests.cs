using System;
using System.Diagnostics;
using System.Windows.Forms;
class DesktopShellTests {
    static int failures;
    static void Check(bool ok,string text) { if(!ok) { failures++; Console.WriteLine("FAIL "+text); } }
    [STAThread] static int Main() {
        int pid=Process.GetCurrentProcess().Id;
        using(var pet=new Form()) using(var settings=new Form()) {
            pet.Text="Dolike isolated shell test"; pet.StartPosition=FormStartPosition.Manual; pet.Left=-3000;
            pet.Show(); Application.DoEvents();
            var settingsHandle=settings.Handle;
            long before=DesktopShell.GetLong(settingsHandle,-20).ToInt64();
            Check(DesktopShell.Maintain(pet.Handle,pid,false),"owned widget accepted");
            long ex=DesktopShell.GetLong(pet.Handle,-20).ToInt64(), style=DesktopShell.GetLong(pet.Handle,-16).ToInt64();
            Check((ex&DesktopShell.ToolWindow)!=0 && (ex&DesktopShell.AppWindow)==0,"widget excluded from taskbar");
            Check((style&(DesktopShell.MinimizeBox|DesktopShell.MaximizeBox))==0,"show-desktop minimization disabled");
            Check(!DesktopShell.Maintain(pet.Handle,pid+1,true),"foreign process handle rejected");
            DesktopShell.ShowWindow(pet.Handle,6); Application.DoEvents();
            Check(DesktopShell.IsIconic(pet.Handle),"fixture minimized");
            DesktopShell.Maintain(pet.Handle,pid,true); Application.DoEvents();
            Check(!DesktopShell.IsIconic(pet.Handle) && DesktopShell.IsWindowVisible(pet.Handle),"visible widget restored without activation");
            pet.Hide(); DesktopShell.Maintain(pet.Handle,pid,true);
            Check(!DesktopShell.IsWindowVisible(pet.Handle),"hidden bowl stays hidden");
            Check(DesktopShell.GetLong(settingsHandle,-20).ToInt64()==before,"settings styles untouched");
        }
        Console.WriteLine("Desktop shell native: "+failures+" failures"); return failures==0?0:1;
    }
}
