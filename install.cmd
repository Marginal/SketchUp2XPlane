@echo off
if exist "%APPDATA%\SketchUp\SketchUp 2014\SketchUp\Plugins\" (
	xcopy /g /s /y "%~dp0SU2XPlane" "%APPDATA%\SketchUp\SketchUp 2014\SketchUp\Plugins\SU2XPlane\"
	copy  /d /y "%~dp0SU2XPlane.rb" "%APPDATA%\SketchUp\SketchUp 2014\SketchUp\Plugins\"
) else (
	echo Plugin folder not found - is SketchUp 2014 installed?
	pause
)
