# A Windows toast from czw (WSL), shown as Windows Terminal's, so clicking it brings the
# terminal forward. -OnlyIfAway: skip it when Windows Terminal is already in front.
param([string]$Title, [string]$Message, [switch]$OnlyIfAway)

if ($OnlyIfAway) {
    Add-Type -Namespace Czw -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
'@
    $procId = 0
    [void][Czw.Win]::GetWindowThreadProcessId([Czw.Win]::GetForegroundWindow(), [ref]$procId)
    $front = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
    if ($front -eq "WindowsTerminal") { exit 0 }
}

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$texts = $xml.GetElementsByTagName("text")
[void]$texts.Item(0).AppendChild($xml.CreateTextNode($Title))
[void]$texts.Item(1).AppendChild($xml.CreateTextNode($Message))
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
$toast.Tag = "czw"
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Microsoft.WindowsTerminal_8wekyb3d8bbwe!App").Show($toast)
