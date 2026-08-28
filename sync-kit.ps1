<#
.SYNOPSIS
  Copy the canonical chrome from _Kit\template into one or more domain projects.

.DESCRIPTION
  _Kit is NOT a dependency. Nothing imports it, no package.json references it,
  and it never appears in a Docker build. It is a copy-source: after a sync the
  target project owns every file and builds with _Kit deleted from the disk.

  Files ending .tmpl are rendered, not copied: __DOMAIN__, __DOMAIN_TITLE__ and
  __DEVPORT__ are substituted and the .tmpl suffix dropped.

  A project may keep a .kitignore listing paths it has deliberately customised.
  Those are never overwritten — that is the point of standalone: a domain is
  allowed to diverge, and the sync must not silently undo it.

.EXAMPLE
  .\sync-kit.ps1 -Project Person
  .\sync-kit.ps1 -All -WhatIf
  .\sync-kit.ps1 -Project Person,Company -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string[]]$Project,
  [switch]$All,
  [switch]$Force   # overwrite even files listed in .kitignore
)

$ErrorActionPreference = 'Stop'
$kitRoot  = $PSScriptRoot
$template = Join-Path $kitRoot 'template'
$webRoot  = Split-Path $kitRoot -Parent

# domain slug + title + dev port. Slug must match the ZONES key and basePath.
$DOMAINS = @{
  'Person'         = @{ slug='person';          title='Persons';           port=3010 }
  'Members'        = @{ slug='members';         title='Members';           port=3020 }
  'CashAdvance'    = @{ slug='cash-advance';    title='Cash Advance';      port=3030 }
  'Spm'            = @{ slug='spm';             title='SPM Investment';    port=3040 }
  'CreditRating'   = @{ slug='credit-rating';   title='Credit Rating';     port=3060 }
  'Company'        = @{ slug='company';         title='Companies';         port=3070 }
  'GeneralMeeting' = @{ slug='general-meeting'; title='General Meeting';   port=3090 }
  'CustomerRisk'   = @{ slug='customer-risk';   title='Customer Risk';     port=3100 }
  'System'         = @{ slug='system';          title='System';            port=3110 }
  'Market'         = @{ slug='market';          title='Market';            port=3130 }
  'Project'        = @{ slug='project';         title='Project Management';port=3140 }
  'Mpf'            = @{ slug='mpf';             title='Milan Pars';        port=3150 }
  'Template'       = @{ slug='template';        title='Template';          port=3160 }
}

# ..\domains.json (beside the domain folders) OVERRIDES the table above when it is present
# and valid. Missing or malformed => the table stands and a warning says so, so the
# scaffolder never hard-fails under $ErrorActionPreference = 'Stop' because of the registry.
# The outer map is rebuilt as a Hashtable on purpose: the consumers below use .Keys and
# .ContainsKey(), and PowerShell 5.1 has no ConvertFrom-Json -AsHashtable - a PSCustomObject
# here would make -All silently sync zero projects.
$registry = Join-Path $webRoot 'domains.json'
if (Test-Path $registry) {
  try {
    $reg = [System.IO.File]::ReadAllText($registry) | ConvertFrom-Json
    $map = @{}
    foreach ($row in @($reg.domains)) {
      if ($row.kind -eq 'shell') { continue }   # the Shell is not a kit target
      if (-not $row.folder -or -not $row.slug -or -not $row.title -or -not $row.port) {
        throw "row without folder/slug/title/port: $($row | ConvertTo-Json -Compress)"
      }
      $map[[string]$row.folder] = @{ slug=[string]$row.slug; title=[string]$row.title; port=[int]$row.port }
    }
    if ($map.Count -eq 0) { throw 'no domain rows' }
    $DOMAINS = $map
  } catch {
    Write-Warning "domains.json ignored ($($_.Exception.Message)) - using the built-in table."
  }
}

if ($All)      { $targets = $DOMAINS.Keys | Sort-Object }
elseif ($Project) { $targets = $Project }
else { throw "Specify -Project <name[,name]> or -All. Known: $($DOMAINS.Keys -join ', ')" }

foreach ($name in $targets) {
  if (-not $DOMAINS.ContainsKey($name)) { Write-Warning "unknown project '$name' - skipped"; continue }
  $dest = Join-Path $webRoot $name
  if (-not (Test-Path $dest)) { Write-Warning "$name : folder not found at $dest - skipped"; continue }

  $d = $DOMAINS[$name]

  # .kitignore : one relative path per line, # comments allowed
  $ignore = @()
  $kif = Join-Path $dest '.kitignore'
  if ((Test-Path $kif) -and -not $Force) {
    $ignore = Get-Content $kif | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim().Replace('/','\') }
  }

  $copied = 0; $rendered = 0; $skipped = 0; $preserved = 0

  foreach ($src in (Get-ChildItem $template -Recurse -File)) {
    $rel = $src.FullName.Substring($template.Length + 1)

    if ($ignore | Where-Object { $rel -like $_ -or $rel -like "$_\*" }) { $skipped++; continue }

    $isTmpl = $src.Name.EndsWith('.tmpl')
    $relOut = if ($isTmpl) { $rel.Substring(0, $rel.Length - 5) } else { $rel }
    $out    = Join-Path $dest $relOut

    # never clobber a layout the domain already owns - leave it side by side
    if ($relOut -eq 'app\layout.tsx' -and (Test-Path $out)) {
      $out = Join-Path $dest 'app\layout.kit.tsx'
      $preserved++
    }

    # never clobber .env.local - it holds NEXTAUTH_SECRET and per-machine values
    # that must survive every sync. Land the fresh template beside it instead.
    if ($relOut -eq '.env.local' -and (Test-Path $out)) {
      $out = Join-Path $dest '.env.local.example'
      $preserved++
    }

    $outDir = Split-Path $out -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

    if ($PSCmdlet.ShouldProcess($relOut, "sync into $name")) {
      if ($isTmpl) {
        $text = [System.IO.File]::ReadAllText($src.FullName)
        $text = $text.Replace('__DOMAIN_TITLE__', $d.title).
                      Replace('__DOMAIN__',       $d.slug).
                      Replace('__DEVPORT__',      [string]$d.port)
        # UTF-8 with NO BOM: PowerShell's default adds one, and a BOM makes
        # JSON.parse throw - which is how config files silently reset to defaults.
        [System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding($false)))
        $rendered++
      } else {
        Copy-Item -LiteralPath $src.FullName -Destination $out -Force
        $copied++
      }
    }
  }

  # --- generate i18n\namespaces.ts from this project's OWN namespaces --------
  # The Shell's i18n-provider hard-codes ~100 static imports covering the whole
  # estate. A domain app cannot: those folders do not exist here. So the list is
  # derived from what is actually on disk, and regenerated on every sync.
  $nsRoot = Join-Path $dest 'i18n'
  $infra  = @('messages','common','api-errors','dashboard')
  $ns = @()
  if (Test-Path $nsRoot) {
    $ns = Get-ChildItem $nsRoot -Directory |
          Where-Object { $infra -notcontains $_.Name } |
          Where-Object { (Test-Path (Join-Path $_.FullName 'fa.json')) -or (Test-Path (Join-Path $_.FullName 'en.json')) } |
          Sort-Object Name
  }

  $imp = New-Object System.Collections.Generic.List[string]
  $fa  = New-Object System.Collections.Generic.List[string]
  $en  = New-Object System.Collections.Generic.List[string]
  foreach ($n in $ns) {
    $var = (($n.Name -split '[-_.]') | ForEach-Object { if ($_) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } }) -join ''
    if (Test-Path (Join-Path $n.FullName 'fa.json')) {
      $imp.Add("import fa$var from '@/i18n/$($n.Name)/fa.json';")
      $fa.Add("  '$($n.Name)': fa$var,")
    }
    if (Test-Path (Join-Path $n.FullName 'en.json')) {
      $imp.Add("import en$var from '@/i18n/$($n.Name)/en.json';")
      $en.Add("  '$($n.Name)': en$var,")
    }
  }

  $nl  = [Environment]::NewLine
  $gen = @(
    "// GENERATED by _Kit\sync-kit.ps1 - do not edit by hand.",
    "// Re-run:  .\sync-kit.ps1 -Project $name",
    "//",
    "// Lists only the namespaces this project owns. Adding a namespace means",
    "// adding the folder under i18n\ and re-running the sync.",
    "",
    ($imp -join $nl),
    "",
    "export const DOMAIN_NAMESPACES = {",
    "  fa: {",
    ($fa -join $nl),
    "  },",
    "  en: {",
    ($en -join $nl),
    "  },",
    "} as const;",
    ""
  ) -join $nl

  if ($PSCmdlet.ShouldProcess('i18n\namespaces.ts', "generate for $name")) {
    New-Item -ItemType Directory -Force -Path $nsRoot | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $nsRoot 'namespaces.ts'), $gen, (New-Object System.Text.UTF8Encoding($false)))
  }

  "{0,-16} copied={1,-5} rendered={2,-3} kitignored={3,-3} layout-preserved={4} namespaces={5}" -f $name, $copied, $rendered, $skipped, $preserved, $ns.Count
}
