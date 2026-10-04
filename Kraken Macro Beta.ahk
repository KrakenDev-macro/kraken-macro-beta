;@Ahk2Exe-SetName Kraken Macro Beta
;@Ahk2Exe-SetDescription Kraken Macro Beta
;@Ahk2Exe-SetCompanyName KrakenDev
;@Ahk2Exe-SetCopyright Copyright (c) KrakenDev
;@Ahk2Exe-SetVersion 0.1.0
;@Ahk2Exe-UpdateManifest 1

#Requires AutoHotkey v2.0
#SingleInstance Force

; Roblox ignores clicks from non-admin scripts, so relaunch as admin
if !A_IsAdmin {
    try Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp
}

CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"
SendMode "Event"
SetMouseDelay 10

; ===== Kraken Macro Beta: Cast -> Shake -> back to Start position -> repeat =====
; F3 = Start / Stop     F5 = Refresh (reload)     F1 = Close     F6 = add bar fill color under mouse
; The Start position is also the cast click point: the mouse goes there when the macro
; starts and again every time the shake finishes.

global CREDIT := "KrakenDev"
global running := false
global holding := false
global excl := []
global capW := 0, capH := 0, hdcMem := 0, hbm := 0, pBits := 0
global baseBuf := 0, curBuf := 0

; presets live in AppData so they can always be written
global presetDir := A_AppData "\Kraken Macro Beta"
global presetFile := presetDir "\presets.txt"

global gui1 := Gui("+AlwaysOnTop +Resize +0x200000", "Kraken Macro Beta")
gui1.SetFont("s9")

AddRow(label, default, sec := false) {
    gui1.Add("Text", (sec ? "Section" : "xs") " w225", label)
    return gui1.Add("Edit", "x+5 yp w75", default)
}

AddCoords() {
    gui1.Add("Text", "xs w16 h22 +0x200", "X")
    ex := gui1.Add("Edit", "x+2 yp w50", "")
    gui1.Add("Text", "x+8 yp w16 h22 +0x200", "Y")
    ey := gui1.Add("Edit", "x+2 yp w50", "")
    gui1.Add("Text", "x+8 yp w16 h22 +0x200", "W")
    ew := gui1.Add("Edit", "x+2 yp w50", "")
    gui1.Add("Text", "x+8 yp w16 h22 +0x200", "H")
    eh := gui1.Add("Edit", "x+2 yp w50", "")
    return [ex, ey, ew, eh]
}

AddColorRow(label) {
    gui1.Add("Text", "xs w42 h22 +0x200", label)
    e := gui1.Add("Edit", "x+4 yp w135", "")
    addB := gui1.Add("Button", "x+4 yp w50 h22", "+Add")
    clrB := gui1.Add("Button", "x+4 yp w45 h22", "Clear")
    addB.OnEvent("Click", (*) => SetTimer(() => PickInto(e), -3000))
    clrB.OnEvent("Click", (*) => e.Value := "")
    return e
}

; ---------- presets bar ----------
gui1.Add("Text", "xm w330", "Presets (pick one, or type a new name and press Save)")
cmbPreset := gui1.Add("ComboBox", "xm w330 r8")
saveBtn := gui1.Add("Button", "xm w105", "Save")
saveBtn.OnEvent("Click", (*) => SavePreset())
loadBtn := gui1.Add("Button", "x+5 yp w105", "Load")
loadBtn.OnEvent("Click", (*) => LoadPreset())
delBtn := gui1.Add("Button", "x+5 yp w105", "Delete")
delBtn.OnEvent("Click", (*) => DeletePreset())

stText := gui1.Add("Text", "xm y+10 w330 Center", "Status: STOPPED   |   F3 start/stop  F5 refresh  F1 close")
creditText := gui1.Add("Text", "xm w330 Center", "Made by " CREDIT)
creditText.SetFont("s9 bold")
chkShow := gui1.Add("Checkbox", "xm y+8", "Show outlines + start marker (red shake, yellow ignore, green bar)")
chkShow.OnEvent("Click", (*) => UpdateOutline())

tab := gui1.Add("Tab3", "xm y+8 w330 h640", ["Cast", "Shake"])

; ================= CAST (+ its radar) =================
tab.UseTab(1)
gui1.Add("Text", "Section w300", "Start / cast position - ONE click point. The mouse starts here and returns here after every loop (empty = center of Roblox window)")
gui1.Add("Text", "xs w16 h22 +0x200", "X")
eSx := gui1.Add("Edit", "x+2 yp w60", "")
gui1.Add("Text", "x+10 yp w16 h22 +0x200", "Y")
eSy := gui1.Add("Edit", "x+2 yp w60", "")
selPosBtn := gui1.Add("Button", "xs w190", "Select position (click on screen)")
selPosBtn.OnEvent("Click", (*) => SelectPoint(eSx, eSy))
rstPosBtn := gui1.Add("Button", "x+5 yp w95", "Reset")
rstPosBtn.OnEvent("Click", (*) => ResetPoint())

gui1.Add("Text", "xs y+12 w300", "Cast timing")
eFirstClick := AddRow("1st click hold time (ms)", "50")
eFirstGap   := AddRow("Delay between 1st click and hold (ms)", "300")
chkPerfect  := gui1.Add("Checkbox", "xs Checked", "Perfect detector (release when the bar is filled)")
eHold       := AddRow("Hold time if detector is off (ms)", "600")
eHMax       := AddRow("Max hold time (ms)", "4000")
ePostCast   := AddRow("Delay after cast (ms)", "1500")
eCycle      := AddRow("Delay before next cast (ms)", "2000")

gui1.Add("Text", "xs y+14 w300", "Cast radar - power bar area (cover the vertical cast bar)")
hc := AddCoords()
eHx := hc[1], eHy := hc[2], eHw := hc[3], eHh := hc[4]
selHoldBtn := gui1.Add("Button", "xs w190", "Select power bar area (drag)")
selHoldBtn.OnEvent("Click", (*) => SelectArea(eHx, eHy, eHw, eHh, "2DCC5A"))
rstHoldBtn := gui1.Add("Button", "x+5 yp w95", "Reset area")
rstHoldBtn.OnEvent("Click", (*) => ResetArea(eHx, eHy, eHw, eHh))
ePerfPct := AddRow("Detector height (% from top of bar)", "8")
eHScan   := AddRow("Detector scan interval (ms)", "5")
eHStep   := AddRow("Detector sample step (px)", "2")
eHTol    := AddRow("Color tolerance (0-255)", "20")
eBar     := AddColorRow("Fill")
gui1.Add("Text", "xs y+8 w300", "Add the fill color: hold a cast, hover the filled part of the bar, press F6.")

; ================= SHAKE (+ its radars) =================
tab.UseTab(2)
gui1.Add("Text", "Section w300", "Shake radar - scan area (empty = whole Roblox window)")
sc := AddCoords()
eAx := sc[1], eAy := sc[2], eAw := sc[3], eAh := sc[4]
selBtn := gui1.Add("Button", "xs w190", "Select shake area (drag)")
selBtn.OnEvent("Click", (*) => SelectArea(eAx, eAy, eAw, eAh, "FF2D2D"))
rstBtn := gui1.Add("Button", "x+5 yp w95", "Reset area")
rstBtn.OnEvent("Click", (*) => ResetArea(eAx, eAy, eAw, eAh))

gui1.Add("Text", "xs y+14 w300", "Ignore area - the shake scan skips this (e.g. the username GUI)")
ic := AddCoords()
eIx := ic[1], eIy := ic[2], eIw := ic[3], eIh := ic[4]
selIgnBtn := gui1.Add("Button", "xs w190", "Select ignore area (drag)")
selIgnBtn.OnEvent("Click", (*) => SelectArea(eIx, eIy, eIw, eIh, "FFD400"))
rstIgnBtn := gui1.Add("Button", "x+5 yp w95", "Reset area")
rstIgnBtn.OnEvent("Click", (*) => ResetArea(eIx, eIy, eIw, eIh))

gui1.Add("Text", "xs y+14 w300", "Shake timing")
eScan      := AddRow("Shake scan interval (ms)", "30")
eClick     := AddRow("Delay before shake click (ms)", "40")
eClickHold := AddRow("Shake click hold time (ms)", "40")
eNextClick := AddRow("Delay before next shake click (ms)", "100")
eTimeout   := AddRow("Stop after no new GUI for (ms)", "8000")
eSens      := AddRow("Sensitivity (0-765, higher = less)", "90")
eMin       := AddRow("Min new GUI size (samples)", "12")
eStep      := AddRow("Sample step (px, higher = faster)", "8")

tab.UseTab()

for ctrl in [eSx, eSy, eAx, eAy, eAw, eAh, eHx, eHy, eHw, eHh, eIx, eIy, eIw, eIh]
    ctrl.OnEvent("Change", (*) => UpdateOutline())

global fields := Map(
    "startX", eSx, "startY", eSy,
    "firstClick", eFirstClick, "firstGap", eFirstGap, "perfectOn", chkPerfect,
    "holdFixed", eHold, "holdMax", eHMax, "postCast", ePostCast, "cycleDelay", eCycle,
    "perfPct", ePerfPct, "holdScan", eHScan, "holdStep", eHStep, "holdTol", eHTol, "fillColors", eBar,
    "holdX", eHx, "holdY", eHy, "holdW", eHw, "holdH", eHh,
    "areaX", eAx, "areaY", eAy, "areaW", eAw, "areaH", eAh,
    "ignoreX", eIx, "ignoreY", eIy, "ignoreW", eIw, "ignoreH", eIh,
    "scanInterval", eScan, "clickDelay", eClick, "clickHold", eClickHold,
    "nextClickDelay", eNextClick, "timeout", eTimeout, "sensitivity", eSens,
    "minSize", eMin, "step", eStep, "showOutline", chkShow)

gui1.OnEvent("Close", (*) => ExitApp())
OnExit((*) => ReleaseAll())
global contentH := 0
gui1.OnEvent("Size", (*) => UpdateScroll())
OnMessage(0x115, OnVScroll)   ; scrollbar
OnMessage(0x20A, OnWheel)     ; mouse wheel
gui1.Show("AutoSize")
gui1.GetClientPos(, , , &fullH)
gui1.GetPos(&gx, , &gw, &gh)
contentH := fullH
gui1.Move(gx, 20, gw, Min(gh, A_ScreenHeight - 120))   ; fit the screen, scroll for the rest
UpdateScroll()
RefreshPresets()

; ---------- phase label (top of screen) ----------
global phaseGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
phaseGui.BackColor := "1E1E1E"
phaseGui.SetFont("s14 bold cWhite")
phaseText := phaseGui.Add("Text", "w460 Center", "Phase 1: Casting")

; ---------- outlines (4 thin bars just outside each area) + start marker ----------
MakeBars(color) {
    arr := []
    Loop 4 {
        b := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        b.BackColor := color
        arr.Push(b)
    }
    return arr
}
global barsShake := MakeBars("FF2D2D")
global barsHold := MakeBars("2DCC5A")
global barsIgnore := MakeBars("FFD400")
global pointMark := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
pointMark.BackColor := "00E5FF"

F3:: ToggleMacro()
F5:: Reload()
F1:: ExitApp()
F6:: PickInto(eBar)   ; hold a cast, hover the filled part of the bar, press F6

ToggleMacro() {
    global running
    running := !running
    if running {
        phaseGui.Show("NA y8 x" ((A_ScreenWidth - 490) // 2))
        SetPhase(1, "Casting")
        SetTimer(MacroLoop, -10)
    } else {
        phaseGui.Hide()
        ReleaseAll()
        stText.Value := "Status: STOPPED   |   F3 start"
    }
}

SetPhase(n, name) {
    txt := "Phase " n ": " name
    phaseText.Value := txt
    stText.Value := "Status: RUNNING   |   " txt
}

; ---------- mouse helpers ----------
HoldDown() {
    global holding
    if !holding {
        Click "Down"
        holding := true
    }
}

HoldUp() {
    global holding
    if holding {
        Click "Up"
        holding := false
    }
}

ReleaseAll() {
    global holding
    try Click "Up"
    holding := false
}

; ---------- presets (own simple file format, saved in AppData\Kraken Macro Beta) ----------
LoadAllPresets() {
    data := Map()
    data.CaseSense := "Off"
    if !FileExist(presetFile)
        return data
    cur := ""
    for line in StrSplit(FileRead(presetFile, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "")
            continue
        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            cur := SubStr(line, 2, StrLen(line) - 2)
            data[cur] := Map()
        } else if (cur != "") {
            p := InStr(line, "=")
            if (p > 1)
                data[cur][SubStr(line, 1, p - 1)] := SubStr(line, p + 1)
        }
    }
    return data
}

WriteAllPresets(data) {
    DirCreate presetDir
    out := ""
    for name, kv in data {
        out .= "[" name "]`n"
        for k, v in kv
            out .= k "=" v "`n"
        out .= "`n"
    }
    f := FileOpen(presetFile, "w", "UTF-8")
    f.Write(out)
    f.Close()
}

RefreshPresets() {
    cur := cmbPreset.Text
    cmbPreset.Delete()
    try {
        names := []
        for name in LoadAllPresets()
            names.Push(name)
        if (names.Length)
            cmbPreset.Add(names)
    }
    cmbPreset.Text := cur
}

SavePreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Type a preset name first, then press Save"
        return
    }
    if RegExMatch(name, "[\[\]=]") {
        stText.Value := "Preset names can't contain [ ] or ="
        return
    }
    try {
        data := LoadAllPresets()
        kv := Map()
        for key, ctrl in fields
            kv[key] := ctrl.Value
        data[name] := kv
        WriteAllPresets(data)
    } catch as err {
        MsgBox "Could not save the preset:`n" err.Message "`n`nFile: " presetFile
        return
    }
    RefreshPresets()
    cmbPreset.Text := name
    stText.Value := "Preset saved: " name
}

LoadPreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Pick a preset to load first"
        return
    }
    try {
        data := LoadAllPresets()
    } catch as err {
        MsgBox "Could not read the presets:`n" err.Message "`n`nFile: " presetFile
        return
    }
    if !data.Has(name) {
        stText.Value := "Preset not found: " name
        return
    }
    kv := data[name]
    for key, ctrl in fields {
        if !kv.Has(key)
            continue
        if (ctrl.Type = "Checkbox")
            ctrl.Value := (kv[key] = "1") ? 1 : 0
        else
            ctrl.Value := kv[key]
    }
    UpdateOutline()
    stText.Value := "Preset loaded: " name
}

DeletePreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Pick a preset to delete first"
        return
    }
    try {
        data := LoadAllPresets()
        if !data.Has(name) {
            stText.Value := "Preset not found: " name
            return
        }
        data.Delete(name)
        WriteAllPresets(data)
    } catch as err {
        MsgBox "Could not delete the preset:`n" err.Message
        return
    }
    cmbPreset.Text := ""
    RefreshPresets()
    stText.Value := "Preset deleted: " name
}

; ---------- scrolling for the main window ----------
UpdateScroll() {
    global contentH
    if (contentH <= 0)
        return
    gui1.GetClientPos(, , , &vh)
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0xF, si, 4)
    NumPut("int", 0, si, 8)
    NumPut("int", contentH - 1, si, 12)
    NumPut("uint", vh, si, 16)
    NumPut("int", ScrollPos(), si, 20)
    DllCall("SetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si, "int", 1)
    maxPos := Max(0, contentH - vh)
    if (ScrollPos() > maxPos)
        ScrollTo(maxPos)
}

ScrollPos() {
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0x4, si, 4)
    DllCall("GetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si)
    return NumGet(si, 20, "int")
}

ScrollTo(newPos) {
    gui1.GetClientPos(, , , &vh)
    newPos := Max(0, Min(newPos, Max(0, contentH - vh)))
    cur := ScrollPos()
    if (newPos = cur)
        return
    DllCall("ScrollWindowEx", "ptr", gui1.Hwnd, "int", 0, "int", cur - newPos
        , "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "uint", 7)
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0x4, si, 4)
    NumPut("int", newPos, si, 20)
    DllCall("SetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si, "int", 1)
}

OnVScroll(wParam, lParam, msg, hwnd) {
    if (hwnd != gui1.Hwnd)
        return
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0x17, si, 4)
    DllCall("GetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si)
    page := NumGet(si, 16, "uint")
    pos := NumGet(si, 20, "int")
    track := NumGet(si, 24, "int")
    switch (wParam & 0xFFFF) {
        case 0: pos -= 30
        case 1: pos += 30
        case 2: pos -= page
        case 3: pos += page
        case 4, 5: pos := track
        case 6: pos := 0
        case 7: pos := contentH
    }
    ScrollTo(pos)
    return 0
}

OnWheel(wParam, lParam, msg, hwnd) {
    MouseGetPos , , &under
    if (under != gui1.Hwnd)
        return
    d := (wParam >> 16) & 0xFFFF
    if (d >= 0x8000)
        d -= 0x10000
    ScrollTo(ScrollPos() - (d // 120) * 60)
    return 0
}

; ---------- small helpers ----------
Num(ctrl, fallback) {
    try
        return Integer(ctrl.Value)
    catch
        return fallback
}

PickInto(ctrl) {
    MouseGetPos &x, &y
    c := Format("{:06X}", PixelGetColor(x, y) & 0xFFFFFF)
    ctrl.Value := (Trim(ctrl.Value) = "") ? c : ctrl.Value . "," . c
}

; parses "RRGGBB,RRGGBB" into [[r,g,b], ...]
ColorList(ctrl) {
    list := []
    for part in StrSplit(ctrl.Value, ",") {
        part := Trim(part)
        if (part = "")
            continue
        try {
            v := Integer("0x" . part)
            list.Push([(v >> 16) & 255, (v >> 8) & 255, v & 255])
        }
    }
    return list
}

Matches(list, r, g, b, tol) {
    for col in list {
        if (Abs(r - col[1]) <= tol && Abs(g - col[2]) <= tol && Abs(b - col[3]) <= tol)
            return true
    }
    return false
}

; ---------- regions / positions ----------
GetRegion(&l, &t, &w, &h) {
    if WinExist("ahk_exe RobloxPlayerBeta.exe")
        WinGetClientPos &l, &t, &w, &h, "ahk_exe RobloxPlayerBeta.exe"
    else {
        l := 0, t := 0, w := A_ScreenWidth, h := A_ScreenHeight
    }
}

; an area from its 4 boxes, or the whole Roblox window if empty
GetArea(ex, ey, ew, eh, &l, &t, &w, &h, wl, wt, ww, wh) {
    w := Num(ew, 0), h := Num(eh, 0)
    if (w > 0 && h > 0) {
        l := Num(ex, 0), t := Num(ey, 0)
    } else {
        l := wl, t := wt, w := ww, h := wh
    }
}

; Start position = the single cast click point (center of the Roblox window if not set)
HasStartPoint() {
    return (Trim(eSx.Value) != "" && Trim(eSy.Value) != "")
}

GetStartPoint(&px, &py, wl, wt, ww, wh) {
    if HasStartPoint() {
        px := Num(eSx, 0), py := Num(eSy, 0)
    } else {
        px := wl + ww // 2, py := wt + wh // 2
    }
}

MoveToStart(wl, wt, ww, wh) {
    GetStartPoint(&px, &py, wl, wt, ww, wh)
    MouseMove px, py, 0
}

ResetPoint() {
    eSx.Value := "", eSy.Value := ""
    UpdateOutline()
}

ResetArea(ex, ey, ew, eh) {
    ex.Value := "", ey.Value := "", ew.Value := "", eh.Value := ""
    UpdateOutline()
}

UpdateOutline() {
    DrawBars(barsShake, eAx, eAy, eAw, eAh)
    DrawBars(barsHold, eHx, eHy, eHw, eHh)
    DrawBars(barsIgnore, eIx, eIy, eIw, eIh)
    if (chkShow.Value && HasStartPoint())
        pointMark.Show("NA x" (Num(eSx, 0) - 7) " y" (Num(eSy, 0) - 7) " w14 h14")
    else
        pointMark.Hide()
}

DrawBars(arr, ex, ey, ew, eh) {
    w := Num(ew, 0), h := Num(eh, 0)
    if (!chkShow.Value || w <= 0 || h <= 0) {
        for b in arr
            b.Hide()
        return
    }
    x := Num(ex, 0), y := Num(ey, 0), t := 3
    arr[1].Show("NA x" (x - t) " y" (y - t) " w" (w + 2 * t) " h" t)
    arr[2].Show("NA x" (x - t) " y" (y + h) " w" (w + 2 * t) " h" t)
    arr[3].Show("NA x" (x - t) " y" y " w" t " h" h)
    arr[4].Show("NA x" (x + w) " y" y " w" t " h" h)
}

; click ONCE anywhere on screen to set the start / cast point (Esc = cancel)
SelectPoint(ex, ey) {
    ToolTip "Click once where the macro should click and start (Esc = cancel)"
    ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
    ov.BackColor := "000000"
    ov.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent 40, "ahk_id " ov.Hwnd
    Sleep 200
    while !GetKeyState("LButton", "P") {
        if GetKeyState("Escape", "P") {
            ToolTip
            ov.Destroy()
            return
        }
        Sleep 10
    }
    MouseGetPos &x, &y
    KeyWait "LButton"
    ToolTip
    ov.Destroy()
    ex.Value := x, ey.Value := y
    UpdateOutline()
}

; drag a rectangle on screen to set an area (Esc = cancel)
SelectArea(ex, ey, ew, eh, color) {
    ToolTip "Drag with the left mouse button to select the area (Esc = cancel)"
    ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
    ov.BackColor := "000000"
    ov.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent 60, "ahk_id " ov.Hwnd
    box := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    box.BackColor := color

    Sleep 200
    while !GetKeyState("LButton", "P") {
        if GetKeyState("Escape", "P") {
            ToolTip
            ov.Destroy(), box.Destroy()
            return
        }
        Sleep 10
    }
    MouseGetPos &x1, &y1
    box.Show("NA x" x1 " y" y1 " w2 h2")
    WinSetTransparent 130, "ahk_id " box.Hwnd
    while GetKeyState("LButton", "P") {
        MouseGetPos &x2, &y2
        box.Move(Min(x1, x2), Min(y1, y2), Abs(x2 - x1) + 2, Abs(y2 - y1) + 2)
        Sleep 10
    }
    MouseGetPos &x2, &y2
    ToolTip
    ov.Destroy(), box.Destroy()

    w := Abs(x2 - x1), h := Abs(y2 - y1)
    if (w > 5 && h > 5) {
        ex.Value := Min(x1, x2), ey.Value := Min(y1, y2)
        ew.Value := w, eh.Value := h
        UpdateOutline()
    }
}

; ---------- screen capture (fast, in memory) ----------
InitCapture(w, h) {
    global capW, capH, hdcMem, hbm, pBits, baseBuf, curBuf
    if (capW = w && capH = h && hdcMem)
        return
    if hdcMem {
        DllCall("DeleteObject", "ptr", hbm)
        DllCall("DeleteDC", "ptr", hdcMem)
    }
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    pBits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdcS, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    capW := w, capH := h
    baseBuf := Buffer(w * h * 4)
    curBuf := Buffer(w * h * 4)
}

Grab(l, t, w, h) {
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    DllCall("BitBlt", "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hdcS, "int", l, "int", t, "uint", 0x00CC0020)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    DllCall("RtlMoveMemory", "ptr", curBuf, "ptr", pBits, "uptr", w * h * 4)
}

SaveBaseline(w, h) {
    DllCall("RtlMoveMemory", "ptr", baseBuf, "ptr", curBuf, "uptr", w * h * 4)
}

; rectangles (relative to the shake scan area) the shake scan must ignore:
; our own windows + the ignore area
ComputeExclusions(sl, st) {
    global excl
    excl := []
    for g in [gui1, phaseGui] {
        try {
            g.GetPos(&gx, &gy, &gw, &gh)
            excl.Push([gx - sl - 6, gy - st - 6, gx - sl + gw + 6, gy - st + gh + 6])
        }
    }
    iw := Num(eIw, 0), ih := Num(eIh, 0)
    if (iw > 0 && ih > 0) {
        ix := Num(eIx, 0), iy := Num(eIy, 0)
        excl.Push([ix - sl, iy - st, ix - sl + iw, iy - st + ih])
    }
}

; true if a point (relative to the shake area) is inside any ignored rectangle
InExcl(x, y) {
    for r in excl {
        if (x >= r[1] && x < r[3] && y >= r[2] && y < r[4])
            return true
    }
    return false
}

; ---------- shake scan: find a NEW GUI (something that wasn't there before) ----------
FindNewGui(w, h, sens, minArea, step, &ox, &oy) {
    step := Max(2, step)
    bs := step * 8
    xs := [], ys := []
    counts := Map()
    y := 0
    while y < h {
        row := y * w
        x := 0
        while x < w {
            skip := false
            for r in excl {
                if (x >= r[1] && x < r[3] && y >= r[2] && y < r[4]) {
                    skip := true
                    break
                }
            }
            if skip {
                x += step
                continue
            }
            off := (row + x) * 4
            a := NumGet(baseBuf, off, "uint")
            c := NumGet(curBuf, off, "uint")
            if (a != c) {
                d := Abs((a & 255) - (c & 255)) + Abs(((a >> 8) & 255) - ((c >> 8) & 255)) + Abs(((a >> 16) & 255) - ((c >> 16) & 255))
                if (d > sens) {
                    xs.Push(x), ys.Push(y)
                    k := (x // bs) * 10000 + (y // bs)
                    counts[k] := counts.Get(k, 0) + 1
                }
            }
            x += step
        }
        y += step
    }
    if (xs.Length < minArea)
        return false

    ; densest cluster of changes = the new GUI (ignores scattered noise)
    bestK := 0, best := 0
    for k, cnt in counts {
        if (cnt > best)
            best := cnt, bestK := k
    }
    mx := bestK // 10000, my := Mod(bestK, 10000)
    sx := 0, sy := 0, total := 0
    i := 1
    while i <= xs.Length {
        if (Abs(xs[i] // bs - mx) <= 1 && Abs(ys[i] // bs - my) <= 1)
            sx += xs[i], sy += ys[i], total++
        i++
    }
    if (total < minArea)
        return false
    ox := sx // total, oy := sy // total
    return true
}

; ---------- perfect detector: count fill-colored samples in the capture ----------
CountFill(w, h, cols, tol, step) {
    n := 0
    y := 0
    while y < h {
        row := y * w
        x := 0
        while x < w {
            c := NumGet(curBuf, (row + x) * 4, "uint")
            if Matches(cols, (c >> 16) & 255, (c >> 8) & 255, c & 255, tol)
                n++
            x += step
        }
        y += step
    }
    return n
}

; ---------- click helper for shakes ----------
ClickAt(x, y, beforeMs, holdMs) {
    MouseMove x, y, 0
    Sleep 15
    MouseMove x + 1, y + 1, 0
    MouseMove x, y, 0
    Sleep beforeMs
    Click "Down"
    Sleep holdMs
    Click "Up"
}

; ================= CAST: click, then click again and hold =================
DoCast(wl, wt, ww, wh) {
    GetStartPoint(&px, &py, wl, wt, ww, wh)       ; the one predetermined cast click point
    MouseMove px, py, 0
    Sleep 15
    MouseMove px + 1, py + 1, 0
    MouseMove px, py, 0

    ; 1) first click
    Click "Down"
    Sleep Num(eFirstClick, 50)
    Click "Up"
    Sleep Num(eFirstGap, 300)
    if !running
        return

    ; 2) second click: press and HOLD, release when the bar is filled (perfect)
    HoldDown()
    fillCols := ColorList(eBar)
    barSet := (Num(eHw, 0) > 0 && Num(eHh, 0) > 0)
    if (chkPerfect.Value && fillCols.Length > 0 && barSet) {
        GetArea(eHx, eHy, eHw, eHh, &hl, &ht, &hw, &hh, wl, wt, ww, wh)
        stripH := Max(2, Round(hh * Num(ePerfPct, 8) / 100))
        InitCapture(hw, stripH)
        tol := Num(eHTol, 20)
        step := Max(1, Num(eHStep, 2))
        scanMs := Num(eHScan, 5)
        maxHold := Num(eHMax, 4000)
        startTick := A_TickCount
        while running && (A_TickCount - startTick < maxHold) {
            Grab(hl, ht, hw, stripH)
            if (CountFill(hw, stripH, fillCols, tol, step) >= 2)
                break                              ; bar filled = perfect
            Sleep scanMs
        }
    } else {
        if chkPerfect.Value
            stText.Value := "Perfect detector needs a power bar area + Fill color - using fixed hold time"
        Sleep Num(eHold, 600)
    }
    HoldUp()                                       ; release = cast
    Sleep Num(ePostCast, 1500)
}

; ================= SHAKE: click every new GUI in the shake radar =================
DoShake(wl, wt, ww, wh) {
    GetArea(eAx, eAy, eAw, eAh, &sl, &st, &sw, &sh, wl, wt, ww, wh)
    InitCapture(sw, sh)
    ComputeExclusions(sl, st)
    Grab(sl, st, sw, sh)
    SaveBaseline(sw, sh)
    lastSeen := A_TickCount
    timeout := Num(eTimeout, 8000)
    while running && (A_TickCount - lastSeen < timeout) {
        Grab(sl, st, sw, sh)
        if FindNewGui(sw, sh, Num(eSens, 90), Num(eMin, 12), Num(eStep, 8), &cx, &cy) {
            if InExcl(cx, cy) {
                SaveBaseline(sw, sh)
                Sleep Num(eScan, 30)
                continue
            }
            lastSeen := A_TickCount
            ClickAt(sl + cx, st + cy, Num(eClick, 40), Num(eClickHold, 40))
            Sleep Num(eNextClick, 100)
        } else {
            SaveBaseline(sw, sh)
        }
        Sleep Num(eScan, 30)
    }
}

; ================= main loop: Start position -> Cast -> Shake -> Start position =================
MacroLoop() {
    global running
    if WinExist("ahk_exe RobloxPlayerBeta.exe")
        WinActivate
    GetRegion(&wl, &wt, &ww, &wh)
    MoveToStart(wl, wt, ww, wh)                     ; go to the starting position when the macro starts

    while running {
        if WinExist("ahk_exe RobloxPlayerBeta.exe")
            WinActivate
        GetRegion(&wl, &wt, &ww, &wh)

        SetPhase(1, "Casting")
        DoCast(wl, wt, ww, wh)
        if !running
            break

        SetPhase(2, "Shaking")
        DoShake(wl, wt, ww, wh)
        if !running
            break

        SetPhase(3, "Finished, restarting loop")
        MoveToStart(wl, wt, ww, wh)                 ; shake finished: back to the starting position
        Sleep Num(eCycle, 2000)
    }
    ReleaseAll()
}
