Set-ExecutionPolicy RemoteSigned
Set-Item WSMan:\localhost\Client\TrustedHosts -Value * -Force

$user = "Seu usuario"
$password = ConvertTo-SecureString "Senha" -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential ($user, $password)

$computerListPath = "C:\Temp\computer_list1.txt"
$computerDonePath = "C:\Temp\computer_done.txt"

if (-not (Test-Path $computerListPath)) {
  Write-Error "Arquivo 'computer_list1.txt' não encontrado em 'C:\Temp\'. Verifique o caminho do arquivo."
  Exit 1
}
if (-not (Test-Path $computerDonePath)) {
  Write-Error "Arquivo 'computer_done.txt' não encontrado em 'C:\Temp\'. Verifique o caminho do arquivo."
  Exit 1
}
$computerDonePath = "C:\Temp\computer_done.txt"

# URLs para download das versões mais recentes do .NET Core e ASP.NET Core
$downloadUrls = @(
    "https://download.visualstudio.microsoft.com/download/pr/747f4a98-2586-4bc6-b828-34f35e384a7d/44225cfd9d365855ec77d00c4812133c/windowsdesktop-runtime-7.0.10-win-x64.exe",
    "https://download.visualstudio.microsoft.com/download/pr/f1777e79-21d8-4ed8-a529-3f212f4b5262/e685f2224f7140dc10bc0e0b47827e3a/aspnetcore-runtime-7.0.10-win-x64.exe"
)

# Versão desejada do .NET Core
$desiredVersion = "7.0.10"

# Lê os hostnames dos computadores
$computers = Get-Content -Path $computerListPath

# Lista para armazenar os computadores não processados
$computersNotProcessed = @()

# Loop através de cada computador
foreach ($computer in $computers) {
    $processed = $false
    Write-Host "Verificando conectividade com o computador: $computer"

    # Testa a conectividade com ping
    $pingable = Test-Connection -ComputerName $computer -Count 1 -Quiet
    if ($pingable) {
        Write-Host "Conectando-se ao computador: $computer"

        # Estabelece uma sessão remota
        $session = New-PSSession -ComputerName $computer -ErrorAction SilentlyContinue

        if ($session) {
            # Obtém as versões instaladas do .NET Core
            $installedVersions = Invoke-Command -Session $session -ScriptBlock {
                Get-ChildItem -Path "C:\Program Files\dotnet\shared\Microsoft.NETCore.App\" -Directory | Select-Object -ExpandProperty Name
            }

            # Verifica se a versão desejada já está instalada
            if ($installedVersions -contains $desiredVersion) {
                Write-Host "A versão desejada do .NET Core ($desiredVersion) já está instalada. Nenhuma ação necessária."
                Add-Content -Path $computerDonePath -Value "$computer - .NET Core Versão $desiredVersion"
                $processed = $true
            } else {
                # Remove as versões existentes
                Write-Host "Removendo versões existentes do .NET Core"
                Invoke-Command -Session $session -ScriptBlock {
                    # Tenta parar qualquer processo usando os arquivos do .NET Core
                    Stop-Process -Name "dotnet" -Force -ErrorAction SilentlyContinue

                    # Remove os arquivos do .NET Core
                    Get-ChildItem -Path "C:\Program Files\dotnet\", "C:\Program Files (x86)\dotnet\" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".dll" -or $_.Extension -eq ".exe" } | ForEach-Object { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
                }

                # Baixa e instala as versões mais recentes do .NET Core e ASP.NET Core
                foreach ($url in $downloadUrls) {
                    Write-Host "Baixando e instalando a partir de $url"
                    Invoke-Command -Session $session -ScriptBlock {
                        $installerPath = "C:\Temp\" + [System.IO.Path]::GetFileName($using:url)
                        Invoke-WebRequest -Uri $using:url -OutFile $installerPath
                        Start-Process -FilePath $installerPath -ArgumentList "/quiet" -Wait
                        Remove-Item -Path $installerPath -Force
                    }
                }

                # Adiciona o computador à lista de concluídos
                Add-Content -Path $computerDonePath -Value "$computer - .NET Core Versão $desiredVersion"
                $processed = $true
            }

            # Fecha a sessão remota
            Remove-PSSession -Session $session
        } else {
            Write-Host "Não foi possível estabelecer uma sessão remota com o computador: $computer"
        }
    } else {
        Write-Host "Não foi possível conectar-se ao computador: $computer"
    }

    # Adiciona o computador à lista de não processados se necessário
    if (-not $processed) {
        $computersNotProcessed += $computer
    }
}

# Atualiza o arquivo computer_list.txt com os computadores não processados
Set-Content -Path $computerListPath -Value $computersNotProcessed

Write-Host "Processamento concluído."
