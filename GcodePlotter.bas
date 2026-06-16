B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10.5
@EndOfDesignText@
Sub Class_Globals
	Private fx As JFX
	Private xui As XUI
	Private CanvasPane As B4XView
	Private PathCanvas As B4XCanvas
	Private ParentForm As Form
    
	' File tracking collections
	Private GCodeLines As List
	Private FileLoaded As Boolean = False
    
	' Bound limit boxes
	Private MinX, MaxX, MinY, MaxY, MinZ, MaxZ As Double
	Private CenterX, CenterY, CenterZ As Double
	Private GlobalScale As Double = 1.0
    
	' Projection Matrix Orientation angles
	Private AngleX As Double = -35.0
	Private AngleY As Double = 45.0
	Private ActiveViewMode As String = "ISO"
    
	' Mouse interaction
	Private LastMouseX, LastMouseY As Double
	
	' For cursor highlight
	Private CurrentLineIndex As Int = -1
	
	' For panning
	Private PanX As Double = 0
	Private PanY As Double = 0
	
	' JavaObject for wheel handling
	Private PaneJO As JavaObject
End Sub

Public Sub Initialize (TargetForm As Form, TargetPane As Pane)
	ParentForm = TargetForm
	CanvasPane = TargetPane
    
	PathCanvas.Initialize(CanvasPane)
    
	' Create overlay for mouse events
	Dim OverlayPane As Pane
	OverlayPane.Initialize("PlotterMouse")
	CanvasPane.AddView(OverlayPane, 0, 0, CanvasPane.Width, CanvasPane.Height)

	GCodeLines.Initialize
	
	' Set up the explicit JavaFX Scroll Listener (from your working example)
	PaneJO = OverlayPane
	Dim EventListener As Object = PaneJO.CreateEvent("javafx.event.EventHandler", "PaneScroll", Null)
	
	' Target the specific SCROLL event field
	Dim ScrollEventType As JavaObject
	ScrollEventType.InitializeStatic("javafx.scene.input.ScrollEvent")
	Dim ScrollType As Object = ScrollEventType.GetField("SCROLL")
	
	PaneJO.RunMethod("addEventHandler", Array(ScrollType, EventListener))
End Sub

' --- Reading Mouse Buttons for Panning ---
Private Sub PlotterMouse_MouseClicked (EventData As MouseEvent)
	If EventData.PrimaryButtonPressed Then
		' Left click - can be used later
	Else If EventData.SecondaryButtonPressed Then
		' Right click - can be used later
	Else If EventData.MiddleButtonPressed Then
		' Middle click - reset view
		ResetView
	End If
End Sub

Private Sub PlotterMouse_MousePressed (EventData As MouseEvent)
	LastMouseX = EventData.X
	LastMouseY = EventData.Y
End Sub

Private Sub PlotterMouse_MouseDragged (EventData As MouseEvent)
	If FileLoaded = False Then Return
    
	Dim CurrentMouseX As Double = EventData.X
	Dim CurrentMouseY As Double = EventData.Y
	Dim DeltaX As Double = CurrentMouseX - LastMouseX
	Dim DeltaY As Double = CurrentMouseY - LastMouseY
    
	' Right button for panning
	If EventData.SecondaryButtonDown Then
		PanX = PanX + DeltaX
		PanY = PanY + DeltaY
		RenderToolpath
	Else If EventData.PrimaryButtonDown Then
		' Left button for rotation (only in ISO view)
		If ActiveViewMode = "ISO" Then
			AngleY = AngleY + (DeltaX * 0.5)
			AngleX = AngleX - (DeltaY * 0.5)
			RenderToolpath
		End If
	End If
    
	LastMouseX = CurrentMouseX
	LastMouseY = CurrentMouseY
End Sub

' --- Working Mouse Wheel Scroll Handler (from your example) ---
Sub PaneScroll_Event (MethodName As String, Args() As Object) As Object
	' Grab the native event object directly
	Dim NativeEvent As JavaObject = Args(0)
    
	' Pull the vertical scroll distance safely
	Dim DeltaY As Double = NativeEvent.RunMethod("getDeltaY", Null)
    
	' Filter out micro system drifts
	If DeltaY <> 0 Then
		Dim zoomFactor As Double = 1.0
		If DeltaY > 0 Then
			zoomFactor = 1.1  ' Zoom in
		Else
			zoomFactor = 0.9  ' Zoom out
		End If
        
		GlobalScale = GlobalScale * zoomFactor
        
		' Limit zoom
		If GlobalScale < 0.1 Then GlobalScale = 0.1
		If GlobalScale > 1000 Then GlobalScale = 1000
        
		RenderToolpath
	End If
    
	' Prevent the scroll from bubbling away
	NativeEvent.RunMethod("consume", Null)
	Return Null
End Sub

Public Sub LoadAndPlotFile
	Dim fc As FileChooser
	fc.Initialize
	fc.Title = "Select G-Code File"
	fc.SetExtensionFilter("G-Code Files", Array As String("*.nc", "*.gcode", "*.tap"))
    
	Dim SelectedFile As String = fc.ShowOpen(ParentForm)
	If SelectedFile <> "" Then
		Dim LastSlash As Int = SelectedFile.LastIndexOf("\")
		Dim Folder As String = SelectedFile.SubString2(0, LastSlash)
		Dim FileNameStr As String = SelectedFile.SubString(LastSlash + 1)
        
		GCodeLines = File.ReadList(Folder, FileNameStr)
		FileLoaded = True
        
		CalculateFileBoundaries
		TriggerZoomAll
	End If
End Sub

Private Sub CalculateFileBoundaries
	MinX = 99999: MaxX = -99999
	MinY = 99999: MaxY = -99999
	MinZ = 99999: MaxZ = -99999
	
	Dim CurX As Double = 0, CurY As Double = 0, CurZ As Double = 0
	
	For Each LineStr As String In GCodeLines
		LineStr = LineStr.ToUpperCase.Trim
		If LineStr.StartsWith("(") Or LineStr.StartsWith(";") Or LineStr.Length = 0 Then Continue
		
		Dim MatchX As Matcher = Regex.Matcher("X([\-]?[0-9.]+)", LineStr)
		If MatchX.Find Then CurX = UnpackMatch(MatchX)
		Dim MatchY As Matcher = Regex.Matcher("Y([\-]?[0-9.]+)", LineStr)
		If MatchY.Find Then CurY = UnpackMatch(MatchY)
		Dim MatchZ As Matcher = Regex.Matcher("Z([\-]?[0-9.]+)", LineStr)
		If MatchZ.Find Then CurZ = UnpackMatch(MatchZ)
        
		If CurX < MinX Then MinX = CurX
		If CurX > MaxX Then MaxX = CurX
		If CurY < MinY Then MinY = CurY
		If CurY > MaxY Then MaxY = CurY
		If CurZ < MinZ Then MinZ = CurZ
		If CurZ > MaxZ Then MaxZ = CurZ
	Next
	
	If MinX > MaxX Then MinX = 0: MaxX = 10
	If MinY > MaxY Then MinY = 0: MaxY = 10
	If MinZ > MaxZ Then MinZ = 0: MaxZ = 5
	
	CenterX = (MinX + MaxX) / 2
	CenterY = (MinY + MaxY) / 2
	CenterZ = (MinZ + MaxZ) / 2
End Sub

Private Sub RenderToolpath
	If CanvasPane.IsInitialized = False Then Return
	PathCanvas.ClearRect(PathCanvas.TargetRect)
	If FileLoaded = False Then Return
    
	Dim CurX As Double = 0, CurY As Double = 0, CurZ As Double = 0
	Dim IsFirst As Boolean = True
	Dim LineCounter As Int = 0
    
	Dim ViewCenterX As Double = CanvasPane.Width / 2
	Dim ViewCenterY As Double = CanvasPane.Height / 2
    
	Dim RadX As Double = AngleX * 3.14159265 / 180.0
	Dim RadY As Double = AngleY * 3.14159265 / 180.0
    
	Dim CosX As Double = Cos(RadX), SinX As Double = Sin(RadX)
	Dim CosY As Double = Cos(RadY), SinY As Double = Sin(RadY)
    
	Dim LastScreenX As Double = 0, LastScreenY As Double = 0
    
	For Each LineStr As String In GCodeLines
		LineStr = LineStr.ToUpperCase.Trim
		
		If LineStr.StartsWith("(") Or LineStr.StartsWith(";") Or LineStr.Length = 0 Then
			LineCounter = LineCounter + 1
			Continue
		End If
        
		Dim ValidMove As Boolean = False
		Dim MatchX As Matcher = Regex.Matcher("X([\-]?[0-9.]+)", LineStr)
		If MatchX.Find Then
			CurX = UnpackMatch(MatchX)
			ValidMove = True
		End If
		Dim MatchY As Matcher = Regex.Matcher("Y([\-]?[0-9.]+)", LineStr)
		If MatchY.Find Then
			CurY = UnpackMatch(MatchY)
			ValidMove = True
		End If
		Dim MatchZ As Matcher = Regex.Matcher("Z([\-]?[0-9.]+)", LineStr)
		If MatchZ.Find Then
			CurZ = UnpackMatch(MatchZ)
			ValidMove = True
		End If
        
		Dim RelX As Double = CurX - CenterX
		Dim RelY As Double = CurY - CenterY
		Dim RelZ As Double = CurZ - CenterZ
        
		Dim RotX As Double = RelX
		Dim RotY As Double = RelY
        
		Select ActiveViewMode
			Case "TOP"
				RotX = RelX: RotY = RelY
			Case "FRONT"
				RotX = RelX: RotY = -RelZ
			Case "SIDE"
				RotX = RelY: RotY = -RelZ
			Case "ISO"
				Dim FormX As Double = RelX * CosY - RelY * SinY
				Dim FormY As Double = RelX * SinY + RelY * CosY
				RotX = FormX
				RotY = FormY * CosX - RelZ * SinX
		End Select
		
		' Apply pan and zoom to screen coordinates
		Dim ScreenX As Double = ViewCenterX + PanX + (RotX * GlobalScale)
		Dim ScreenY As Double = ViewCenterY + PanY - (RotY * GlobalScale)
		
		If IsFirst = False And ValidMove Then
			Dim StrokeColor As Int = xui.Color_Cyan
			
			' Color based on cursor position
			If CurrentLineIndex >= 0 And LineCounter <= CurrentLineIndex Then
				StrokeColor = 0xFF00FF00   ' Bright Green for processed
			Else
				StrokeColor = 0xFF00FFFF   ' Cyan for future
			End If
			
			If LineStr.Contains("G0 ") Or LineStr.Contains("G00") Then StrokeColor = xui.Color_Red
            
			PathCanvas.DrawLine(LastScreenX, LastScreenY, ScreenX, ScreenY, StrokeColor, 1.2)
		End If
        
		LastScreenX = ScreenX
		LastScreenY = ScreenY
		IsFirst = False
		LineCounter = LineCounter + 1
	Next
    
	PathCanvas.Invalidate
End Sub

Private Sub UnpackMatch(M As Matcher) As Double
	Try
		Dim Res As Double = M.Group(1)
		Return Res
	Catch
		Return 0
	End Try
End Sub

Public Sub SetViewProjection (Mode As String)
	ActiveViewMode = Mode
	Select Mode
		Case "TOP":   AngleX = 0:   AngleY = 0
		Case "FRONT": AngleX = 90:  AngleY = 0
		Case "SIDE":  AngleX = 90:  AngleY = 90
		Case "ISO":   AngleX = -35: AngleY = 45
	End Select
	RenderToolpath
End Sub

Public Sub TriggerZoomAll
	If FileLoaded = False Then Return
	If CanvasPane.IsInitialized = False Then Return
	Dim UsableW As Double = CanvasPane.Width * 0.8
	Dim UsableH As Double = CanvasPane.Height * 0.8
    
	Dim WidthDelta As Double = MaxX - MinX
	Dim HeightDelta As Double = MaxY - MinY
	If WidthDelta = 0 Then WidthDelta = 1
	If HeightDelta = 0 Then HeightDelta = 1
    
	GlobalScale = Min(UsableW / WidthDelta, UsableH / HeightDelta)
	RenderToolpath
End Sub

Public Sub TriggerZoomDelta (Factor As Double)
	GlobalScale = GlobalScale * Factor
	RenderToolpath
End Sub

Public Sub RefreshPlotterLayout
	If CanvasPane.IsInitialized Then
		PathCanvas.Initialize(CanvasPane)
		RenderToolpath
	End If
End Sub

' Reset pan and zoom to original view
Public Sub ResetView
	PanX = 0
	PanY = 0
	TriggerZoomAll
End Sub

' ============================================================
' METHODS FOR TEXT VIEWER
' ============================================================

Public Sub GetGCodeLines As List
	Return GCodeLines
End Sub

Public Sub LoadFileFromPath(Folder As String, FileName As String)
	GCodeLines = File.ReadList(Folder, FileName)
	FileLoaded = True
	CalculateFileBoundaries
	TriggerZoomAll
	CurrentLineIndex = 0
	PanX = 0
	PanY = 0
End Sub

Public Sub SetCursorToLine(lineIndex As Int)
	If lineIndex < 0 Or lineIndex >= GCodeLines.Size Then Return
	CurrentLineIndex = lineIndex
	RenderToolpath
End Sub