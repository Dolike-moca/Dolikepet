using System;
using System.Diagnostics;
using System.Windows.Forms;
class DesktopShellTests {
    static int failures;
    static void Check(bool ok,string text) { if(!ok) { failures++; Console.WriteLine("FAIL "+text); } }
    [STAThread] static int Main() {
        int pid=Process.GetCurrentProcess().Id;
        using(var pet=new Form()) using(var settings=new Form()) using(var chat=new Form()) {
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
            chat.Left=-3000; chat.Show(); Application.DoEvents();
            long chatStyle=DesktopShell.GetLong(chat.Handle,-16).ToInt64();
            Check(DesktopShell.Maintain(chat.Handle,pid,false,false),"chat registered without desktop-widget policy");
            Check((DesktopShell.GetLong(chat.Handle,-20).ToInt64()&DesktopShell.ToolWindow)!=0,"chat excluded from taskbar");
            Check(DesktopShell.GetLong(chat.Handle,-16).ToInt64()==chatStyle,"chat keeps normal window controls");
            DesktopShell.ShowWindow(chat.Handle,6); Application.DoEvents();
            DesktopShell.Maintain(chat.Handle,pid,true,false);
            Check(DesktopShell.IsIconic(chat.Handle),"chat stays minimized during show-desktop maintenance");
            chat.Hide(); DesktopShell.Maintain(chat.Handle,pid,false,false);
            Check(!DesktopShell.IsWindowVisible(chat.Handle),"hidden chat stays hidden");
            chat.Show(); DesktopShell.Maintain(chat.Handle,pid,false,false);
            Check((DesktopShell.GetLong(chat.Handle,-20).ToInt64()&DesktopShell.AppWindow)==0,"reopened chat stays out of taskbar");
        }
        Console.WriteLine("Desktop shell native: "+failures+" failures"); return failures==0?0:1;
    }
}
