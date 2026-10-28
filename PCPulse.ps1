param([switch]$SmokeTest, [switch]$SelfTest, [string]$PreviewPath)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:previous = @{}
$script:lastSample = [datetime]::UtcNow
$script:rows = @()
$script:labels = @{}
$stateDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PCPulse'
$stateFile = Join-Path $stateDirectory 'preferences.json'
if (Test-Path $stateFile) {
    try {
        $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        foreach ($property in $saved.PSObject.Properties) { $script:labels[$property.Name] = [string]$property.Value }
    } catch { Write-Warning 'Could not read preferences. Starting with no labels.' }
}

function Get-Snapshot {
    $now = [datetime]::UtcNow
    $elapsed = [math]::Max(0.1, ($now - $script:lastSample).TotalSeconds)
    $next = @{}
    $groups = @{}
    foreach ($process in Get-Process) {
        try {
            $name = $process.ProcessName
            if ($process.Id -eq 0) { continue }
            $cpu = $process.TotalProcessorTime.TotalSeconds
            $key = '{0}:{1}' -f $process.Id, $process.StartTime.ToUniversalTime().Ticks
            $usage = 0.0
            if ($script:previous.ContainsKey($key)) {
                $usage = [math]::Max(0, ($cpu - $script:previous[$key]) / $elapsed / [Environment]::ProcessorCount * 100)
            }
            $next[$key] = $cpu
            if (-not $groups.ContainsKey($name)) {
                $groups[$name] = [pscustomobject]@{ Name=$name; CPU=0.0; MemoryMB=0.0; Count=0; Label='Unreviewed'; Review='' }
            }
            $groups[$name].CPU += $usage
            $groups[$name].MemoryMB += $process.WorkingSet64 / 1MB
            $groups[$name].Count++
        } catch {
            # Processes can exit or deny access during sampling.
        } finally { $process.Dispose() }
    }
    $script:previous = $next
    $script:lastSample = $now
    foreach ($entry in $groups.Values) {
        if ($script:labels.ContainsKey($entry.Name)) { $entry.Label = $script:labels[$entry.Name] }
        if ($entry.Label -eq 'Rarely use' -and ($entry.CPU -ge 1 -or $entry.MemoryMB -ge 200)) {
            $entry.Review = 'Worth reviewing'
        }
        $entry.CPU = [math]::Round([math]::Min(100, $entry.CPU), 1)
        $entry.MemoryMB = [math]::Round($entry.MemoryMB, 1)
        $entry
    }
}

if ($SmokeTest) {
    $null = @(Get-Snapshot)
    Start-Sleep -Seconds 1
    $sample = @(Get-Snapshot)
    if ($sample.Count -lt 1) { throw 'No processes collected.' }
    if (@($sample | Where-Object { $_.CPU -lt 0 -or $_.CPU -gt 100 -or $_.MemoryMB -lt 0 }).Count) { throw 'Invalid resource values.' }
    [pscustomobject]@{ Status='PASS'; ProcessGroups=$sample.Count; TopMemory=($sample | Sort-Object MemoryMB -Descending | Select-Object -First 3 Name,CPU,MemoryMB) } | ConvertTo-Json -Depth 4
    exit
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'PC Pulse | See what is using your PC'
$form.Size = New-Object System.Drawing.Size(1180, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 740)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#10151D')
$form.ForeColor = [System.Drawing.Color]::WhiteSmoke
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = New-Object System.Windows.Forms.Padding(32,24,32,20)
$layout.ColumnCount = 1
$layout.RowCount = 10
foreach ($height in @(46,36,118,52,48,0,28,58,30,22)) {
    $style = New-Object System.Windows.Forms.RowStyle
    if ($height -eq 0) { $style.SizeType = 'Percent'; $style.Height=100 } else { $style.SizeType='Absolute'; $style.Height=$height }
    $null = $layout.RowStyles.Add($style)
}
$form.Controls.Add($layout)

function Add-Text($text, $size, $row) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleLeft'
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $size)
    $layout.Controls.Add($label,0,$row)
    return $label
}
$title = Add-Text 'PC Pulse' 27 0
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',27)
$subtitle = Add-Text 'A little clarity for everything running in the background.' 11 1
$subtitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#92A0B3')

$cards = New-Object System.Windows.Forms.TableLayoutPanel
$cards.Dock='Fill'
$cards.ColumnCount=3
$cards.Margin=New-Object System.Windows.Forms.Padding(0,12,0,10)
foreach ($unused in 1..3) { $null=$cards.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',33.333))) }
$layout.Controls.Add($cards,0,2)
function New-MetricCard($column,$caption,$hint,$accent) {
    $panel=New-Object System.Windows.Forms.Panel
    $panel.Dock='Fill'
    $panel.Margin=New-Object System.Windows.Forms.Padding(0,0,12,0)
    $panel.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#1A2330')
    $stripe=New-Object System.Windows.Forms.Panel
    $stripe.Dock='Left'; $stripe.Width=3
    $stripe.BackColor=[System.Drawing.ColorTranslator]::FromHtml($accent)
    $panel.Controls.Add($stripe)
    $heading=New-Object System.Windows.Forms.Label
    $heading.Text=$caption; $heading.Location=New-Object System.Drawing.Point(18,10)
    $heading.Size=New-Object System.Drawing.Size(260,19)
    $heading.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#9AA9BC')
    $heading.Font=New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $panel.Controls.Add($heading)
    $value=New-Object System.Windows.Forms.Label
    $value.Text='--'; $value.Location=New-Object System.Drawing.Point(15,29)
    $value.Size=New-Object System.Drawing.Size(270,39)
    $value.Font=New-Object System.Drawing.Font('Segoe UI Semibold',24)
    $panel.Controls.Add($value)
    $detail=New-Object System.Windows.Forms.Label
    $detail.Text=$hint; $detail.Location=New-Object System.Drawing.Point(18,73)
    $detail.Size=New-Object System.Drawing.Size(290,18)
    $detail.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#8493A7')
    $detail.Font=New-Object System.Drawing.Font('Segoe UI',9)
    $panel.Controls.Add($detail)
    $cards.Controls.Add($panel,$column,0)
    return $value
}
$cpuMetric=New-MetricCard 0 'SAMPLED CPU' 'Across accessible processes' '#52D6BC'
$memoryMetric=New-MetricCard 1 'PROCESS MEMORY' 'Combined working sets, including shared RAM' '#8C9EFF'
$reviewMetric=New-MetricCard 2 'WORTH A LOOK' 'Heavy processes you marked as rarely used' '#F1BF71'
$section = Add-Text 'Your running processes' 14 3
$section.Font=New-Object System.Drawing.Font('Segoe UI Semibold',14)

$filters = New-Object System.Windows.Forms.FlowLayoutPanel
$filters.Dock='Fill'
$filters.Margin=New-Object System.Windows.Forms.Padding(0)
$filters.WrapContents=$false
$searchLabel=New-Object System.Windows.Forms.Label
$searchLabel.Text='Search'; $searchLabel.AutoSize=$true
$searchLabel.Margin=New-Object System.Windows.Forms.Padding(0,7,10,0)
$searchLabel.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#9AA9BC')
$search = New-Object System.Windows.Forms.TextBox
$search.Width=280
$search.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#202C3B')
$search.ForeColor=[System.Drawing.Color]::WhiteSmoke
$search.BorderStyle='FixedSingle'
$search.Margin=New-Object System.Windows.Forms.Padding(0,3,16,0)
$search.AccessibleName='Search process names'
$sort = New-Object System.Windows.Forms.ComboBox
$sort.DropDownStyle='DropDownList'
$sort.Width=180
$sort.FlatStyle='Flat'
$sort.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#202C3B')
$sort.ForeColor=[System.Drawing.Color]::WhiteSmoke
$sort.Margin=New-Object System.Windows.Forms.Padding(0,3,18,0)
$sort.Items.AddRange(@('Highest memory','Highest CPU','Process name'))
$sort.SelectedIndex=0
$reviewOnly = New-Object System.Windows.Forms.CheckBox
$reviewOnly.Text='Rarely used only'
$reviewOnly.AutoSize=$true
$reviewOnly.Margin=New-Object System.Windows.Forms.Padding(0,6,0,0)
$filters.Controls.AddRange(@($searchLabel,$search,$sort,$reviewOnly))
$layout.Controls.Add($filters,0,4)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock='Fill'
$grid.ReadOnly=$true
$grid.AllowUserToAddRows=$false
$grid.AllowUserToDeleteRows=$false
$grid.RowHeadersVisible=$false
$grid.MultiSelect=$false
$grid.SelectionMode='FullRowSelect'
$grid.AutoSizeColumnsMode='Fill'
$grid.BackgroundColor=[System.Drawing.Color]::FromArgb(28,34,46)
$grid.BorderStyle='None'
$grid.Margin=New-Object System.Windows.Forms.Padding(0)
$grid.CellBorderStyle='SingleHorizontal'
$grid.GridColor=[System.Drawing.ColorTranslator]::FromHtml('#283345')
$grid.ColumnHeadersBorderStyle='None'
$grid.ColumnHeadersHeightSizeMode='DisableResizing'
$grid.ColumnHeadersHeight=42
$grid.AllowUserToResizeRows=$false
$grid.DefaultCellStyle.Padding=New-Object System.Windows.Forms.Padding(10,0,6,0)
$grid.ColumnHeadersDefaultCellStyle.Padding=New-Object System.Windows.Forms.Padding(10,0,0,0)
$grid.ColumnHeadersDefaultCellStyle.Font=New-Object System.Drawing.Font('Segoe UI Semibold',9)
$grid.EnableHeadersVisualStyles=$false
$grid.ColumnHeadersDefaultCellStyle.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#202B3A')
$grid.ColumnHeadersDefaultCellStyle.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#9EACC0')
$grid.DefaultCellStyle.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#18212D')
$grid.AlternatingRowsDefaultCellStyle.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#1B2532')
$grid.DefaultCellStyle.ForeColor=[System.Drawing.Color]::WhiteSmoke
$grid.DefaultCellStyle.SelectionBackColor=[System.Drawing.ColorTranslator]::FromHtml('#234A50')
$grid.DefaultCellStyle.SelectionForeColor=[System.Drawing.Color]::White
$grid.RowTemplate.Height=42
foreach ($column in @(@('Name','Process'),@('CPU','CPU %'),@('MemoryMB','RAM (MB)'),@('Count','Processes'),@('Label','Your label'),@('Review','Review'))) {
    $null=$grid.Columns.Add($column[0],$column[1])
}
$grid.Columns['Name'].FillWeight=150
$grid.Columns['Review'].FillWeight=140
$grid.Columns['CPU'].DefaultCellStyle.Format='0.0'
$grid.Columns['MemoryMB'].DefaultCellStyle.Format='N1'
$grid.Columns['Name'].DefaultCellStyle.Font=New-Object System.Drawing.Font('Segoe UI Semibold',10)
foreach ($column in $grid.Columns) { $column.SortMode='NotSortable' }
$layout.Controls.Add($grid,0,5)
$selectionHint=Add-Text 'Select a process, then choose how often you use it.' 9 6
$selectionHint.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#92A0B3')

$actions=New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock='Fill'
$actions.Margin=New-Object System.Windows.Forms.Padding(0,8,0,0)
$layout.Controls.Add($actions,0,7)
function Save-Label($label) {
    if ($grid.SelectedRows.Count -eq 0) { return }
    $name=[string]$grid.SelectedRows[0].Cells['Name'].Value
    $script:labels[$name]=$label
    try {
        $null=New-Item -ItemType Directory -Path $stateDirectory -Force
        $script:labels | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    } catch { [System.Windows.Forms.MessageBox]::Show('Could not save your label: '+$_.Exception.Message) | Out-Null }
    foreach ($entry in $script:rows) { if ($entry.Name -eq $name) { $entry.Label=$label; $entry.Review= if ($label -eq 'Rarely use' -and ($entry.CPU -ge 1 -or $entry.MemoryMB -ge 200)) {'Worth reviewing'} else {''} } }
    Update-Grid
}
foreach ($caption in @('Rarely use','Keep','Unreviewed')) {
    $button=New-Object System.Windows.Forms.Button
    $button.Text=$caption
    $button.Width=145
    $button.Height=38
    $button.FlatStyle='Flat'
    $button.FlatAppearance.BorderSize=0
    $button.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#293648')
    $button.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#DDE7F4')
    $button.Font=New-Object System.Drawing.Font('Segoe UI Semibold',10)
    $button.Margin=New-Object System.Windows.Forms.Padding(0,0,10,0)
    $button.Cursor=[System.Windows.Forms.Cursors]::Hand
    if ($caption -eq 'Rarely use') {
        $button.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#52D6BC')
        $button.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#102A29')
    }
    $button.Add_Click({ Save-Label $this.Text })
    $actions.Controls.Add($button)
}
$summary=Add-Text 'LIVE  /  Collecting the first sample...' 9 8
$summary.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#52D6BC')
$footnote=Add-Text 'Review hint: rarely used + at least 1% CPU or 200 MB RAM. Labels and measurements stay on your PC.' 9 9
$footnote.ForeColor=[System.Drawing.ColorTranslator]::FromHtml('#8493A7')

function Update-Grid {
    $selected= if ($grid.SelectedRows.Count) { [string]$grid.SelectedRows[0].Cells['Name'].Value } else { '' }
    $items=@($script:rows | Where-Object { $_.Name.IndexOf($search.Text,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and (-not $reviewOnly.Checked -or $_.Label -eq 'Rarely use') })
    $items= switch ($sort.SelectedIndex) { 1 { $items | Sort-Object CPU,MemoryMB -Descending }; 2 { $items | Sort-Object Name }; default { $items | Sort-Object MemoryMB -Descending } }
    $scroll=$grid.FirstDisplayedScrollingRowIndex
    $grid.SuspendLayout()
    $grid.Rows.Clear()
    foreach ($entry in $items) {
        $index=$grid.Rows.Add($entry.Name,$entry.CPU,$entry.MemoryMB,$entry.Count,$entry.Label,$entry.Review)
        if ($entry.Review) { $grid.Rows[$index].DefaultCellStyle.ForeColor=[System.Drawing.Color]::FromArgb(255,205,114) }
        if ($entry.Name -eq $selected) { $grid.Rows[$index].Selected=$true; $grid.CurrentCell=$grid.Rows[$index].Cells[0] }
    }
    if ($scroll -ge 0 -and $scroll -lt $grid.Rows.Count) { $grid.FirstDisplayedScrollingRowIndex=$scroll }
    $grid.ResumeLayout()
    $cpuMetric.Text='{0:N1}%' -f ($script:rows | Measure-Object CPU -Sum).Sum
    $memoryMetric.Text='{0:N2} GB' -f (($script:rows | Measure-Object MemoryMB -Sum).Sum / 1024)
    $reviewMetric.Text=[string]@($script:rows | Where-Object Review).Count
    $section.Text='Your running processes   /   '+$grid.Rows.Count
}
$search.Add_TextChanged({ Update-Grid })
$sort.Add_SelectedIndexChanged({ Update-Grid })
$reviewOnly.Add_CheckedChanged({ Update-Grid })
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=2500
$timer.Add_Tick({
    try {
        $script:rows=@(Get-Snapshot)
        $totalCPU=($script:rows | Measure-Object CPU -Sum).Sum
        $flagged=@($script:rows | Where-Object Review).Count
        $summary.Text='LIVE  /  Refreshes every 2.5 seconds     /     Last updated '+(Get-Date -Format 'HH:mm:ss')
        Update-Grid
    } catch { $summary.Text='Refresh failed. Retrying: '+$_.Exception.Message }
})
$form.Add_Shown({ $script:rows=@(Get-Snapshot); Update-Grid; $timer.Start() })
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
if ($SelfTest) {
    $form.Add_Shown({
        try {
            if ($grid.Rows.Count -lt 1) { throw 'Grid did not populate.' }
            $search.Text='__pcpulse_no_matching_process__'
            if ($grid.Rows.Count -ne 0) { throw 'Search filtering failed.' }
            $search.Text=''
            $sort.SelectedIndex=1
            $reviewOnly.Checked=$true
            foreach ($row in $grid.Rows) { if ($row.Cells['Label'].Value -ne 'Rarely use') { throw 'Rarely used filter failed.' } }
            $reviewOnly.Checked=$false
            if ($grid.Rows.Count -lt 1) { throw 'Resetting filters failed.' }
            $script:selfTestPassed=$true
        } catch { Write-Error $_; $script:selfTestFailed=$true }
        finally { $form.Close() }
    })
}
if ($PreviewPath) {
    $form.Add_Shown({
        $timer.Stop()
        $previewTimer=New-Object System.Windows.Forms.Timer
        $previewTimer.Interval=1200
        $previewTimer.Add_Tick({
        $this.Stop()
        $script:rows=@(Get-Snapshot)
        Update-Grid
        $summary.Text='LIVE  /  Refreshes every 2.5 seconds     /     Last updated '+(Get-Date -Format 'HH:mm:ss')
        $form.Refresh()
        $bitmap=New-Object System.Drawing.Bitmap($form.Width,$form.Height)
        try {
            $form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
            $bitmap.Save($PreviewPath,[System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose(); $this.Dispose(); $form.Close() }
        })
        $previewTimer.Start()
    })
}
[System.Windows.Forms.Application]::Run($form)
$form.Dispose()
if ($script:selfTestFailed) { exit 1 }
if ($SelfTest) {
    if (-not $script:selfTestPassed) { throw 'UI test did not complete.' }
    Write-Output 'PASS: populated grid, search, CPU sorting, rarely used filter, reset.'
}
