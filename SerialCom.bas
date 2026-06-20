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
	Private isSending As Boolean = False
	Private currentFileLines As List
	Private currentLineIndex As Int = 0
	Private currentFileName As String = ""
End Sub

Public Sub Initialize(Callback As Object)
	serial.Initialize("serial")
	mCallback = Callback
	currentFileLines.Initialize
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
			If mCallback <> Null Then
				CallSub2(mCallback, "SerialMessageReceived", ln)
			End If
		End If
	Next
End Sub

' Send a G-code file line by line (blocking - use in background thread)
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

' Non-blocking file loader
Public Sub PrepareFileForSending(gcodeFile As String)
	currentFileLines.Clear
	currentLineIndex = 0
	currentFileName = gcodeFile
	
	Dim tr As TextReader
	tr.Initialize(File.OpenInput("", gcodeFile))
	Dim ln As String
	
	Do While True
		ln = tr.ReadLine
		If ln = Null Then Exit
		ln = ln.Trim
		If ln.Length > 0 And Not ln.StartsWith(";") Then
			currentFileLines.Add(ln)
		End If
	Loop
	tr.Close
	
	Log("Prepared " & currentFileLines.Size & " lines from " & gcodeFile)
End Sub

' Start sending the prepared file
Public Sub StartFileSending
	If currentFileLines.Size = 0 Then
		Log("No file prepared for sending")
		Return
	End If
	
	If isSending Then
		Log("Already sending a file")
		Return
	End If
	
	isSending = True
	currentLineIndex = 0
	SendNextLine
End Sub

' Send the next line
Private Sub SendNextLine
	If isSending And currentLineIndex < currentFileLines.Size Then
		Dim line As String = currentFileLines.Get(currentLineIndex)
		Send(line & CRLF)
		currentLineIndex = currentLineIndex + 1
		
		If mCallback <> Null Then
			CallSub3(mCallback, "FileProgressUpdate", currentLineIndex, currentFileLines.Size)
		End If
	Else If currentLineIndex >= currentFileLines.Size Then
		isSending = False
		If mCallback <> Null Then
			CallSub1(mCallback, "FileSendComplete")
		End If
	End If
End Sub

Public Sub PauseFile
	isSending = False
	Send("!")
	Log("File transmission paused")
End Sub

Public Sub ResumeFile
	If currentLineIndex < currentFileLines.Size Then
		isSending = True
		Send("~")
		Log("File transmission resumed")
		SendNextLine
	End If
End Sub

Public Sub AbortFile
	isSending = False
	currentLineIndex = 0
	currentFileLines.Clear
	Send(Chr(24))
	Log("File transmission aborted")
End Sub

Public Sub IsFileSending As Boolean
	Return isSending
End Sub

Public Sub GetCurrentFileName As String
	Return currentFileName
End Sub

Public Sub GetTotalLines As Int
	Return currentFileLines.Size
End Sub

Public Sub GetCurrentLineIndex As Int
	Return currentLineIndex
End Sub
