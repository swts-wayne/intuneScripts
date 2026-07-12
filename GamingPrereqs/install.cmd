@echo off

echo Installing VC++ 2013 x86...
"%~dp0VC2013\vcredist_x86.exe" /install /quiet /norestart

echo Installing VC++ 2013 x64...
"%~dp0VC2013\vcredist_x64.exe" /install /quiet /norestart

echo Installing VC++ 2015-2022 x86...
"%~dp0VC2022\vc_redist.x86.exe" /install /quiet /norestart

echo Installing VC++ 2015-2022 x64...
"%~dp0VC2022\vc_redist.x64.exe" /install /quiet /norestart

echo Extracting DirectX...
mkdir "%TEMP%\DXRedist" 2>nul

"%~dp0DirectX\directx_Jun2010_redist.exe" /Q /T:%TEMP%\DXRedist

echo Installing DirectX...
"%TEMP%\DXRedist\DXSETUP.exe" /silent

exit /b 0