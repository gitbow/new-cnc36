B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10.5
@EndOfDesignText@
Sub Class_Globals
	Private serial As Serial
	Private astream As AsyncStreams
	Private mCallback As Object
	Private lastLine As String        ' holds the most recent complete line
End Sub

Public Sub Initialize(Callback As Object)
	serial.Initialize("serial")
	mCallback = Callback
End Sub

Public Sub OpenPort(PortName As String)
	serial.Open(PortName)
	serial.SetParams(115200, 8, 1, 0)
	astream.Initialize(serial.GetInputStream, serial.GetOutputStream, "astream")
	Log("Opened " & PortName & " at 115200 baud")
End Sub

Public Sub Send(data As String)
	Dim b() As Byte = data.GetBytes("UTF8")
	astream.Write(b)
End Sub

' Handle incoming data
Private Sub astream_NewData (Buffer() As Byte)
	Dim msg As String = BytesToString(Buffer, 0, Buffer.Length, "UTF8")
	' Split into lines by CRLF
	Dim parts() As String = Regex.Split(CRLF, msg)
	For Each ln As String In parts
		ln = ln.Trim
		If ln.Length > 0 Then
			lastLine = ln
			CallSub2(mCallback, "SerialMessageReceived", ln)
		End If
	Next
End Sub

' Send a G-code file line by line
Public Sub SendFile(gcodeFile As String)
	Dim tr As TextReader
	tr.Initialize(File.OpenInput("", gcodeFile))
	Dim ln As String
    
	Do While True
		ln = tr.ReadLine
		If ln = Null Then Exit
		ln = ln.Trim
		If ln.Length > 0 Then
			Send(ln & CRLF)   ' send line with newline
			WaitForOK         ' wait until controller replies "ok"
		End If
	Loop
    
	tr.Close
End Sub

' Wait until lastLine contains "ok" or "error"
Private Sub WaitForOK
	Do While True
		Sleep(50)
		If lastLine <> "" Then
			Dim response As String = lastLine.Trim.ToLowerCase
			If response.StartsWith("ok") Then Exit
			If response.StartsWith("error") Then
				Log("GRBL Error: " & response)
				Exit
			End If
		End If
	Loop
End Sub




'Sub Class_Globals
'	Private serial As Serial
'	Private astream As AsyncStreams
'	Private mCallback As Object
'	Private buffer As StringBuilder   ' accumulates incoming data
'	Private lastLine As String        ' stores the most recent complete line
' 
'End Sub
'
'Public Sub Initialize(Callback As Object)
'	serial.Initialize("serial")
'	mCallback = Callback
'	buffer.Initialize
'End Sub
'
'Public Sub OpenPort(PortName As String)
'	serial.Open(PortName)
'	serial.SetParams(115200, 8, 1, 0)
'	astream.Initialize(serial.GetInputStream, serial.GetOutputStream, "astream")
'	Log("Opened " & PortName & " at 115200 baud")
'End Sub
'
'Public Sub Send(data As String)
'	Dim b() As Byte = data.GetBytes("UTF8")
'	astream.Write(b)
'End Sub
'
'' Collect incoming data and split into lines
'Private Sub astream_NewData (buffer() As Byte)
'	' Convert incoming bytes to a string
'	Dim msg As String = BytesToString(buffer, 0, buffer.Length, "UTF8")
'
'	' Split into lines by CRLF
'	Dim parts() As String = Regex.Split(CRLF, msg)
'	For Each ln As String In parts
'		ln = ln.Trim
'		If ln.Length > 0 Then
'			lastLine = ln
'			CallSub2(mCallback, "SerialMessageReceived", ln)
'		End If
'	Next
'End Sub
'
'
'' Send a G-code file line by line' --- Add these at the end of your module ---
'
'' Send a G-code file line by line
'Public Sub SendFile(gcodeFile As String)
'	Dim tr As TextReader
'	tr.Initialize(File.OpenInput("", gcodeFile))
'	Dim ln As String
'    
'	Do While True
'		ln = tr.ReadLine
'		If ln = Null Then Exit
'		ln = ln.Trim
'		If ln.Length > 0 Then
'			Send(ln & CRLF)    ' send line with newline
'			WaitForOK          ' wait until controller replies "ok"
'		End If
'	Loop
'    
'	tr.Close
'End Sub
'
'' Wait until lastLine contains "ok" or "error"
'Private Sub WaitForOK
'	Do
'		Sleep(50)
'		If lastLine <> "" Then
'			Dim response As String = lastLine.Trim.ToLowerCase
'			If response.StartsWith("ok") Then Exit
'			If response.StartsWith("error") Then
'				Log("GRBL Error: " & response)
'				Exit
'			End If
'		End If
'	Loop
'End Sub
