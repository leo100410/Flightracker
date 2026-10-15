$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$photoRoot = Join-Path $PSScriptRoot 'Sources/RadarCore/Resources'
Get-ChildItem -LiteralPath $photoRoot -Filter 'ModelPhoto-*.jpg' | ForEach-Object {
    $photoBytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $photoStream = [System.IO.MemoryStream]::new($photoBytes, 0, $photoBytes.Length)
    $photoImage = [System.Drawing.Image]::FromStream($photoStream)
    try {
        $photoScale = [Math]::Min(1.0, [Math]::Min(480.0 / $photoImage.Width, 320.0 / $photoImage.Height))
        if ($photoScale -lt 1.0) {
            $photoThumb = $photoImage.GetThumbnailImage([int]($photoImage.Width * $photoScale), [int]($photoImage.Height * $photoScale), $null, [IntPtr]::Zero)
            try { $photoThumb.Save($_.FullName, [System.Drawing.Imaging.ImageFormat]::Jpeg) }
            finally { $photoThumb.Dispose() }
        }
    } finally { $photoImage.Dispose(); $photoStream.Dispose() }
}
