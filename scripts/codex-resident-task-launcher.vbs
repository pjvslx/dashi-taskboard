Option Explicit

Dim shell, command, index, exitCode

If WScript.Arguments.Count < 2 Then
  WScript.Quit 2
End If

Function QuoteArgument(value)
  QuoteArgument = Chr(34) & Replace(value, Chr(34), Chr(92) & Chr(34)) & Chr(34)
End Function

Set shell = CreateObject("WScript.Shell")
command = QuoteArgument(WScript.Arguments(0))

For index = 1 To WScript.Arguments.Count - 1
  command = command & " " & QuoteArgument(WScript.Arguments(index))
Next

exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
